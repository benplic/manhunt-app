# Phase 1 Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pure-Python GameSession with Classic modules: geo, roles, head start, zones, fuzzy reveal, signal loss, QR tags, win, and filtered views.

**Architecture:** Deterministic engine. FakeClock. Modules compose via hooks. Views are the anti-cheat boundary.

**Tech Stack:** Python, pytest, Shapely 2. No FastAPI imports in engine/.


## Global Constraints

Copied from `docs/superpowers/plans/2026-11-09-manhunt-roadmap.md`. Every task implicitly includes this section.

- Server: `requires-python >=3.12`, Docker image `python:3.13-slim`. If a wheel fails to install on local Python 3.14, run the tests through `docker compose run --rm server-test` instead.
- iOS: `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SWIFT_VERSION = 5.0`, no Swift packages. Files under `ios/Manhunt/` and `ios/ManhuntTests/` are picked up automatically (synchronized folders). Never add file references to `project.pbxproj`. Only edit build settings there, and only when a task says so.
- **Engine purity:** nothing in `server/app/engine/` imports FastAPI, asyncio, the database, `datetime.now`, or the global `random`. Time comes from `Clock`, randomness from `random.Random(seed)`. All rule timers count **game seconds** (`state.game_elapsed_s`), which do not advance while paused.
- **Visibility:** every outbound state goes through `engine/views.py::build_view(session, viewer_id)`. Seekers never receive a hider's precise location except under the signal-loss safety override or after the game ends. A decoy flag is never sent to seekers. **A seeker who is confidently out of bounds is shown exactly to every player until they re-enter.**
- Readings with `accuracy_m > 30` are for display only. Zone and range decisions ignore them.
- Distances use the flat approximation at **111,320 m per degree** with longitude scaled by `cos(lat0)`, never haversine (the Swift test expects 111.32 m and haversine gives 111.19 m). Polygon containment includes the boundary (Shapely `covers`).
- Error codes come only from the `ErrorCode` list under Contracts, mirrored exactly in Swift.
- No secrets in the repo. Settings come from environment variables; Azure injects Key Vault references through a managed identity. Commit `server/.env.example` with placeholders.
- Logging uses standard `logging`, JSON in Azure, and includes `game_id`/`player_id`. Never log coordinates or tokens.
- Code style (Scott's rules): comment non-obvious logic, mark unfinished work with `TODO:`, raise specific exception types, never swallow errors.
- TDD: write the failing test first; each task ends green and committed.

## Contracts

Copied from the roadmap. Do not invent names.

ErrorCode strings: `UNAUTHORIZED FORBIDDEN NOT_HOST NOT_A_MEMBER VALIDATION_FAILED ARENA_INVALID ARENA_NOT_FOUND PRESET_NOT_FOUND GAME_NOT_FOUND INVALID_JOIN_CODE GAME_FULL WRONG_PHASE NEED_BOTH_ROLES TOKEN_INVALID TOKEN_EXPIRED NOT_IN_PAIRING_RANGE NOT_IN_RANGE TARGET_NOT_ACTIVE TARGET_SHIELDED TARGET_IN_SAFE_ZONE WRONG_ROLE ELIMINATED INSUFFICIENT_POINTS COOLING_DOWN NEEDS_TARGET TARGET_OUTSIDE RATE_LIMITED INTERNAL`

Join alphabet: `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. Meters per degree: `111320`. Accuracy cutoff: `30` m. Default OOB margin: `5` m.

REST prefix `/v1`. Error body `{"error":{"code","message","details"}}`.

Engine: `BaseModule` hooks `on_start/on_tick/on_location/check_tag/on_event/check_win`. `GameSession` methods `add_player, assign_roles_random, set_role, start, pause, resume, end, record_location, claim_tag, tick, emit, drain_events`.

Phases: `lobby -> head_start -> active -> ended`, plus `paused` from `head_start` or `active`.

Arena JSON keys: `lat`/`lon`, zone kinds `safe|out_of_bounds|seeker_spawn`.

Classic module ids: `roles, head_start, reveal_fuzzy, tag_policy, zone_policy, signal_loss, win` with the defaults in the roadmap.

Swift names are pinned by `GameRulesTests.swift`. `ArenaEditorModel` is NOT `@MainActor`. Tool enum is `EditorTool`.


---

## File structure

Create under `server/app/engine/`: `geo.py arena.py clock.py state.py events.py session.py views.py qr.py modules/base.py modules/roles.py modules/head_start.py modules/zone_policy.py modules/reveal_fuzzy.py modules/signal_loss.py modules/tag_policy.py modules/win.py`
Create under `server/tests/engine/`: `conftest.py test_geo.py test_arena.py test_head_start.py test_roles.py test_zone_policy.py test_reveal.py test_signal_loss.py test_tag.py test_views.py helpers.py`

**Interfaces produced for later tasks:** `GameSession`, `build_view(session, viewer_id) -> dict`, `make_qr_token / parse_qr_token`, `classic_preset() -> PresetSnapshot`, `FakeClock`, `run_for(session, clock, seconds)`.

Meters helper in tests (same as Swift Fixtures): `lat = y/111320`, `lon = x/111320`.

### Task 1: geo and arena

Port GameRulesTests geometry/validator/OOB-accuracy with identical numbers.

```python
def meters(x, y):
    return GeoPoint(lat=y / 111_320, lon=x / 111_320)

def test_equator_thousandth_degree():
    d = distance_m(GeoPoint(0, 0), GeoPoint(0.001, 0))
    assert abs(d - 111.32) < 0.05
```

Implement `project` at lat0 using 111320. Shapely Polygon covers for contains. `is_confidently_outside` as specified. `validate_arena` returns list of `{code, name}` matching ArenaIssue cases: self_intersection, play_area_too_small, outside_play_area.

Commit: `feat: port arena geometry and validation to the engine`

### Task 2: session, clock, head start

`FakeClock` with `now` datetime and `advance(seconds)`. `tick` if not paused: `game_elapsed_s += 1` (integer game seconds), then `on_tick` each module.

`start()`: need at least one hider and one seeker else `GameRuleError(NEED_BOTH_ROLES)`. If head_start enabled and duration>0 -> phase head_start else active.

Head start: when `game_elapsed_s >= duration`, phase becomes active.

Pause: set paused=True, store `paused_from`. Resume restores prior phase. Time does not advance while paused.

Tests: duration 12, advance 11 still head_start, +1 active; disable head_start starts active; pause 20s then resume still head_start then 5s -> active.

Commit: `feat: add GameSession phase machine and head start`

### Task 3: roles

`assign_roles_random(hider_count)` uses `random.Random(seed)` shuffle, clamp like Swift. `set_role`. Test empty, all seekers, all hiders, 1 of 4.

Commit: `feat: add role assignment module`

### Task 4: zone policy

Per-player BoundsMachine, same state machine as Swift. Evaluated on tick using last reading if accuracy<=30. Hider penalized -> status eliminated, event "out of bounds". Seeker not inside -> flag `oob_revealed=True` (cleared on re-enter), no eliminate.

Safe zone: if inside a safe circle/polygon, start visit timer; at expiry `safe_expired=True` so tags work; leaving starts cooldown.

Test: hider at (100,-80) accuracy 5 eliminated after warning+countdown 3. Seeker outside appears in views as exact (task 8) and returns.

Commit: `feat: enforce out-of-bounds and safe zones`

### Task 5: fuzzy reveal

On tick, every `interval` game seconds, for each active hider without ghost (ghost is Phase 4; skip if no effect), emit a reveal pin at true position offset by seeded random within `fuzz` meters. Pin lasts `display` seconds. fuzz=0 means exact offset 0.

Commit: `feat: add periodic fuzzy hider reveals`

### Task 6: signal loss

If no location in `silence` wall-clock seconds (use clock.now, not game time — silence is real time including... roadmap says game seconds for rule timers. Spec: "If the server receives no location for the silence threshold". Use clock.now() elapsed, still advances during pause? Safety should advance during pause. Use wall clock from FakeClock, advance even if paused... Simpler: use clock.now always, pause does not stop silence detection because FakeClock.advance is called by tests even when paused only if they call it. In PreviewMatchTests pause freezes head start but they don't test silence during pause. Use clock.now() delta since last location.

On silence: status=signal_lost, banner tone=safety, last location kind last_known visible to all.

Commit: `feat: detect signal loss and broadcast last known location`

### Task 7: QR tags and win

Token: payload `{"g": game_id, "h": hider_id, "exp": unix}` JSON, HMAC-SHA256 with QR key, `urlsafe_b64(payload)+"."+urlsafe_b64(sig)` without padding.

claim_tag via QR: validate sig, exp, game, hider active, seeker is seeker, GPS pairing (distance <= pairing_m + accuracies, both readings accuracy<=30), not in unexpired safe zone, not shielded (Phase 4). Far GPS with fake close UWB still NOT_IN_PAIRING_RANGE (QR uses GPS only; pairing check is GPS).

Tag radius for QR: skip UWB dual range in MVP; GPS pairing + token is enough. Still reject NOT_IN_PAIRING_RANGE when GPS > 30m.

Win: all hiders eliminated -> seekers; time_limit reached -> hiders; either.

Commit: `feat: add QR tag policy and win conditions`

### Task 8: views

`build_view(session, viewer_id)` returns PlayerView dict. Implement visibility rules from Contracts including seeker OOB pins. Test lobby has no locations; seeker cannot see hider exact; everyone sees signal_lost; ended shows all; seeker OOB visible to hiders and gone after re-enter; decoy flag never present.

Commit: `feat: filter PlayerView so hiders stay hidden`
