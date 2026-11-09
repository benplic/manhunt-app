# Phase 1 API and Realtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Postgres, REST, WebSockets, and the bot simulation harness around GameSession.

**Architecture:** SQLAlchemy 2 async + Alembic. SessionManager holds in-memory games. WebSocket authenticates via hello token. Tick loop 1s unless MANHUNT_TICK_LOOP=false.

**Tech Stack:** FastAPI, SQLAlchemy 2, psycopg, Alembic, pytest, starlette TestClient websockets.


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

`server/app/db/{base,models,session}.py`, `server/app/db/migrations/`, `server/alembic.ini`, `server/app/auth/{tokens,deps,routes,apple}.py`, `server/app/arenas/{schemas,routes}.py`, `server/app/presets/{classic,routes}.py`, `server/app/games/{schemas,service,routes,join_code}.py`, `server/app/realtime/{protocol,manager,ws,ratelimit}.py`, `server/tests/api/`, `server/tests/sim/`

### Task 1: DB models and migration

Tables exactly as roadmap 1.9. Partial unique index on games.join_code WHERE status NOT IN ('ended','abandoned'). JSONB for arena_snapshot, preset_snapshot, arena.data. On startup `abandon_orphans()`.

Commit: `feat: add Postgres models and initial Alembic migration`

### Task 2: Auth

JWT HS256 24h, `sub`=user id. POST /v1/auth/dev {display_name} when allowed. POST /v1/auth/apple returns 501 stub. GET /v1/me. Bearer dependency. Tests: prod+dev_auth refuses at startup; local issues token; apple 501.

Commit: `feat: add dev sign-in and session JWTs`

### Task 3: Arenas and presets

CRUD owner-scoped. Validate via engine. GET /v1/presets returns [classic]. Invalid geometry 422 ARENA_INVALID.

Commit: `feat: add arena CRUD and classic preset`

### Task 4: Games REST

Create snapshots arena+preset, generate JoinCode, add host as player. Join by code. Roles/start/pause/resume/end/leave/QR. 20 player cap. Authz: membership, host, phase.

Commit: `feat: add game REST endpoints`

### Task 5: Realtime

SessionManager.get_or_create. WS /v1/games/{id}/ws. hello within 5s. location 2/s drop excess. Fan-out view <=500ms coalesced, heartbeat 5s. QR tokens to hiders every 30s. Persist non-sensitive events.

Commit: `feat: stream game views over WebSocket`

### Task 6: Bot simulation

tests/sim/test_full_games.py with TestClient, FakeClock, manager.tick_all(). Scenarios A-D from the roadmap. Assert no seeker view contains a hider exact location.

Commit: `test: play full games with scripted bot players`
