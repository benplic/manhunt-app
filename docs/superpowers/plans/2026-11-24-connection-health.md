# Connection Health Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut WebSocket disconnects, learn what is actually causing them, and show players their own connection quality with a four-bar indicator beside settings.

**Architecture:** First make the failures observable (exception text, close codes, client platform). Then make the server tolerant of a slow client (concurrent timeout-bounded sends, latest-view-wins, no per-fix DB commit). Then make clients reconnect faster and show a socket meter.

**Tech Stack:** FastAPI/Python with pytest, SwiftUI/XCTest on iOS 18.4, React/TypeScript with Vitest.

Source: playtest logs of 2026-11-23. PS95VZ: 981 `ws_disconnect` (782 `client_close`, 99 `send_failed`, 100 `server_error`), 1,303 reconnects across the night, about 50 to 80 disconnects per five minutes. The log has no exception text and no client platform, so the root cause is unproven. Related plans: `2026-11-24-server-clock-rematch-arena.md`, `2026-11-24-alert-noise.md`.

## Global Constraints

- Do **not** add `requestAlwaysAuthorization`. When In Use plus the existing background location mode and `CLBackgroundActivitySession` is the supported path. Info.plist keeps "Manhunt does not request Always access."
- No secrets or precise coordinates in logs.
- The four-bar meter measures **your socket**, not GPS and not other players.
- Do not commit, push, or deploy. Stop for user review when the plan is done.

---

### Task 1: Observability first

**Files:**
- Modify: `server/app/realtime/ws.py` (the bare `except Exception` that closes with 1011)
- Modify: `server/app/realtime/manager.py` (`broadcast` send-failure path)
- Modify: `server/app/playtest_log.py`
- Modify: `ios/Manhunt/Networking/GameSocket.swift`, `web/src/api/ws.ts` (add `client` to `hello`)
- Test: `server/tests/sim/test_ws_logging.py`

**Interfaces:**
- `hello.data.client = {platform: "ios"|"web", app_version: str, os_version: str}`. Server stores it on the connection and adds it to every `ws_*` log line.
- `ws_disconnect` and `exception` log lines add `exc_type`, `exc_message` (truncated), `close_code`, `send_ms`.

- [ ] Failing tests: the log line for a forced server error contains `exc_type`; `hello` with `client` is echoed on `ws_connect`.
- [ ] Implement. Unknown `client` values must not break old app builds (field optional).
- [ ] After a playtest, answer the open question "is iOS more stable than web" by grouping disconnects per minute by `platform`. Add a small analysis script under `server/scripts/` if useful.

### Task 2: Server tolerates slow clients

**Files:**
- Modify: `server/app/realtime/manager.py` (`broadcast`)
- Modify: `server/app/main.py` (`persist_location`), `server/app/realtime/ws.py` (`handle_location`)
- Test: `server/tests/sim/test_broadcast_slow_client.py`, `server/tests/sim/test_location_persist.py`

- [ ] Failing test: with 27 fake sockets and one that never reads, the other 26 receive each view within a bounded time.
- [ ] Send to all sockets concurrently with a per-socket timeout (suggest 3 s). TODO: tune after measuring.
- [ ] Per-client latest-wins slot: if a send is still in flight when a new view is ready, replace the pending view instead of queuing.
- [ ] Do not detach a player on the first failed send. Allow a short grace (suggest 2 consecutive failures or 5 s) before detaching.
- [ ] Stop committing to Postgres per location message. Stage the event in memory and let the once-per-second persist write it. Keep the per-game persist lock. Check that a server crash loses at most the last second of locations and document it.
- [ ] Keep replay by `last_seq` working. Add a regression test for reconnect catch-up.
- [ ] Run `pytest -q` and `ruff check .`.

### Task 3: Client reconnect behavior

**Files:**
- Modify: `ios/Manhunt/Networking/GameSocket.swift`, `ios/Manhunt/Store/AppStore.swift`
- Modify: `web/src/api/ws.ts`
- Test: iOS XCTest with a fake socket, web Vitest with fake timers

- [ ] iOS: observe `NWPathMonitor`. When the network path becomes satisfied or changes interface, reconnect immediately and reset the backoff.
- [ ] iOS and web: after `welcome`, immediately send the latest known location fix.
- [ ] Web: reconnect on `online` and `visibilitychange` to visible.
- [ ] Keep the 15 s ping. Keep the shared backoff 1, 2, 4, 8, 15 s with jitter. TODO: consider a 10 s cap after measuring.
- [ ] Failing tests for each trigger, and a test that backoff resets after a stable connection.
- [ ] Make sure a host remove or membership close (the existing "do not reconnect" path) is still respected.

### Task 4: Four-bar socket meter

**Files:**
- Modify: `ios/Manhunt/LiveGameView.swift` (top bar next to settings), create `ios/Manhunt/SignalBarsView.swift`
- Modify: `web/src/screens/LiveMap.tsx`, `LiveMap.css`, create `web/src/components/SignalBars.tsx`
- Test: iOS XCTest on the state mapping, web Vitest

**Mapping (decided by the user, 5 second window):** 4 bars = connected and last server message within 5 s; 3 = connected but last message older than 5 s; 2 = reconnecting, first retry; 1 = repeated failures; 0 = down. Make 5 s a named constant.

- [ ] Failing tests for the state mapping function (pure function, both platforms).
- [ ] Add the bars beside settings. Include an accessibility label like "Connection: good" and do not rely on color alone.
- [ ] Tap shows a short explanation and last message age. Route any message through the alert queue, see the alert plan.

### Task 5: Background location check (iOS)

**Files:** `ios/Manhunt/Location/LocationReporter.swift`, `ios/Manhunt/Store/AppStore.swift`

- [ ] Add a manual test script in this plan's notes or `docs/`: start a hunt, lock the phone for 10 minutes, and confirm fixes and the socket keep arriving.
- [ ] If fixes stop, restart `CLLocationUpdate.liveUpdates()` and the background session on foreground. Do not request Always.
- [ ] Record the result in the plan. If it still fails, bring the Always question back to the user with data.

### Task 6: Hosting decision note (no code)

- [ ] Write a short decision note: the server runs on a home machine behind a Cloudflare tunnel. Compare staying put versus Azure Container Apps with a minimum replica of 1, including cost, latency, and operations. Present it to the user. Do not migrate in this plan.

## Edge Cases To Cover

- Network switches from Wi-Fi to cellular mid-hunt.
- Phone in airplane mode and back.
- Server restart during a hunt: clients reconnect and catch up.
- A client sends location while the socket is half-open.
- Duplicate reconnect storms from several triggers at once. Debounce them.

## Done When

- Every disconnect in the log has an exception type or close code and a platform.
- One slow phone no longer delays other players.
- iOS and web both show a socket meter beside settings.
- A repeat playtest shows far fewer disconnects per minute, and the platform comparison is available.

## Execution Notes (agent run, branch cursor/connection-health-c705)

Nothing is committed, pushed, or deployed. Stopped for user review.

- Task 1: done and tested (pytest). New log fields: exc_type, exc_message (truncated, coordinates and token-like strings redacted), close_code, send_ms, platform, app_version, os_version. Analysis script: server/scripts/ws_disconnects_by_platform.py. The "is iOS more stable than web" question needs a repeat playtest.
- Task 2: done and tested. Per-socket outbox with latest-view-wins, 3 s send timeout, detach after 2 consecutive failures or 5 s. Location messages no longer commit; the 1 Hz persist writes them (a crash loses the fixes since the last successful persist, about one tick normally; a clean shutdown flushes once more). Also fixed: an old socket's disconnect used to detach its reconnected replacement.
- Task 3: web done and tested (Vitest). iOS written but not compiled or run (no Xcode on this machine): NWPathMonitor trigger, resend after welcome, stable-connection backoff reset.
- Task 4: web done and tested. iOS written but not compiled or run. Thresholds I chose beyond the user's 5 s window: down after 5 consecutive failures or no network path (named constants, TODO to tune).
- Task 5: iOS foreground restart written, not run. Manual test and result table: docs/testing/background-location-check.md. Result: not run yet.
- Task 6: docs/decisions/2026-11-24-hosting-home-vs-azure.md. Azure per-second rates were not verifiable from the pricing page; confirm in the calculator.

Review follow-up: an independent review found no Critical issues. Fixed: raw exception text on stdout, half-open watchdog on web and iOS, stationary-phone false stale on iOS, per-player-minute in the analysis script, shutdown flush, BOMs. Open: iOS still needs a build on a Mac.

Second review follow-up: no Critical issues. Fixed: bounded and selective shutdown flush (SessionManager.flush_all), analysis script lists platforms with zero disconnects, watchdog covers a socket that opened but never got welcome (web tested; iOS written, untested), narrower early return in ws.py. Deferred: attach-before-replay ordering in ws.py (pre-existing), iOS connect() not closing an old socket (pre-existing), airplane-mode meter parity.

iOS verification (2026-11-25, Mac, Xcode 26.2, iPhone 16 Pro / iOS 18.4): the Swift written on the Windows machine did not compile (`GameSocket.launchRun` assigned a `Task<()?, Never>` to `Task<Void, Never>`). Fixed. After that, `xcodebuild test` passed 250 tests, including `GameSocketHealthTests` (18), `SocketMeterTests` (11) and `LocationFreshnessTests` (7). The Task 5 manual lock-the-phone check in `docs/testing/background-location-check.md` is still not run; it needs a physical phone.
