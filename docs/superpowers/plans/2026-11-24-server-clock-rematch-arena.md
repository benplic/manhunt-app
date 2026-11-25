# Server Clock, Rematch Join Code, and Arena Cap Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each in-game second last one real second, stop abandoned sessions from running forever, make crash recovery idempotent, keep the same join code on rematch, and raise the arena radius cap to 3,000 m.

**Architecture:** The tick loop keeps a monotonic schedule and does persistence and broadcast off the tick so slow I/O cannot stretch game time. Rematch reuses the ended game's join code. The radius cap changes in the API validator and in both clients.

**Tech Stack:** FastAPI/Python engine with pytest, SwiftUI/XCTest on iOS 18.4, React/TypeScript with Vitest.

Source: playtest logs of 2026-11-23. XVAVGR kept shrinking for about an hour after players moved to PS95VZ. PS95VZ revealed about every 75 s of wall time for a 60 s game interval, and after a restart it failed to rebuild with `GameRuleError: TARGET_NOT_ACTIVE`. Related plans: `2026-11-24-connection-health.md` (concurrent broadcast), `2026-11-24-late-join-queue.md` (shares `service.py`).

## Global Constraints

- Game-second semantics do not change: head start, zone shrink, reveal intervals, and signal loss stay in game seconds. Only how game seconds advance changes.
- Do not make game time depend on wall-clock reads inside engine code. Keep the engine deterministic for replay. The realtime layer decides when to call `tick`.
- Tests must not sleep for real seconds. Use an injectable clock or sleep function.
- Do not commit, push, or deploy. Stop for user review when the plan is done.

---

### Task 1: Monotonic tick schedule

**Files:**
- Modify: `server/app/realtime/manager.py` (`tick_loop`, `tick_all`, `broadcast`)
- Modify: `server/app/main.py` (the persist callback wiring)
- Test: `server/tests/sim/test_tick_loop.py` (create if missing)

**Interfaces:**
- `tick_loop` computes the next deadline as `previous_deadline + 1.0` using `time.monotonic()` and sleeps the remainder. If it falls behind by more than N seconds, it ticks once and logs `tick_lag` instead of catching up in a burst. TODO: choose N after measuring (suggest 5 s).
- Persist and broadcast run in separate tasks and never block the schedule. Only one persist or broadcast per game may be in flight. Skip, do not queue, if the previous one is still running.

- [ ] Write a failing test with a fake clock and a slow fake broadcast that proves ticks stay one second apart.
- [ ] Write a failing test that a slow persist does not delay the next tick.
- [ ] Implement the monotonic schedule and detach persist and broadcast.
- [ ] Log `tick_lag_ms` and `broadcast_ms` to the playtest log at DEBUG and WARNING when lag exceeds a threshold.
- [ ] Verify with a local simulation: 27 fake sockets, one slow, game second stays at 1.0 s on average.
- [ ] Run `pytest -q` and `ruff check .`.

### Task 2: End or freeze empty sessions

**Files:**
- Modify: `server/app/realtime/manager.py`, `server/app/games/service.py`
- Test: `server/tests/sim/test_empty_session.py`

- [ ] Define "empty": no connected socket and no member message for a configurable idle time (default 10 minutes, decided by the user).
- [ ] Failing test: a hunt with no sockets for the idle time is frozen (stops ticking) and marked `abandoned` or `paused`. A reconnect wakes a frozen game.
- [ ] Implement it. Log `session_idle_freeze` and `session_idle_wake`.
- [ ] Make sure the smoke-test games (like UXK4HS) also stop.

### Task 3: Idempotent crash recovery

**Files:**
- Modify: `server/app/engine/recovery.py`, `server/app/engine/session.py`
- Test: `server/tests/engine/test_recovery.py`

- [ ] Reproduce: replay a logged input list that tags a hider twice, or whose target is already eliminated, and show `TARGET_NOT_ACTIVE` aborts the rebuild.
- [ ] Make replay treat an already-applied tag or state transition as a no-op with a warning log, while live paths still raise.
- [ ] Add a regression test built from the PS95VZ failure shape (`TARGET_NOT_ACTIVE` in recovery).
- [ ] If a rebuild still fails, mark the game `abandoned` with a clear log line instead of crash-looping on every restart.

### Task 4: Rematch reuses the join code

**Files:**
- Modify: `server/app/games/service.py` (`rematch`, `_host_rematch`, `_join_rematch_lobby`, `_unique_code`)
- Test: `server/tests/games/test_rematch.py`

- [ ] Failing test: after the host rematches, the new lobby has the same `join_code` as the ended game, and a guest who joins with the old code lands in the new lobby.
- [ ] Release the code on the ended row. The join lookup already filters out `ended` and `abandoned`, so the new row can hold the code. Check for a unique constraint on `join_code` and handle it. TODO: if a unique index blocks reuse, make it a partial unique index on non-ended games via a migration.
- [ ] Keep `_join_rematch_lobby` working for players already carried over.
- [ ] Edge cases: two simultaneous rematch requests, rematch of the sample game (`PARK42`), code collision with another live game.
- [ ] Update iOS (`AppStore.rematch`) and web handling if they assume a new code is returned. They should accept the same code.

### Task 5: Arena radius cap 3,000 m

**Files:**
- Modify: `server/app/games/routes.py` (`radius_m: float = Field(ge=30, le=2000)`)
- Modify: `ios/Manhunt/Domain/ArenaValidator.swift`, `ios/Manhunt/Editor/ArenaEditorModel.swift`, editor copy strings
- Modify: `web/src/screens/Home.tsx`, `web/src/screens/Lobby.tsx` (`max={2000}`)
- Test: server validator tests, iOS `ArenaValidator` tests, web tests

- [ ] Failing tests at 2,000, 2,001, 3,000, and 3,001 m on all three layers.
- [ ] Change the limit everywhere. Search for other `2000` radius constants with `rg "2000|2,000"` and check zone shrink minimums and map zoom for a 3 km arena.
- [ ] Check performance: arena containment and polygon checks at 3 km, the zone shrink schedule, and map tile zoom range.
- [ ] Update help text that mentions 2 km.

## Edge Cases To Cover

- Clock catches up after a laptop sleep: no burst of 300 ticks.
- Tick during paused phase still advances wall time but not game time.
- Rematch while someone is still reconnecting.
- Radius exactly at boundaries, and non-numeric input.

## Done When

- 60 game seconds takes 60 s of wall time within a small tolerance, even with a slow client.
- Abandoned sessions stop ticking.
- A restart no longer fails on an already-eliminated target.
- Rematch keeps the join code.
- The arena cap is 3,000 m on server, iOS, and web.
