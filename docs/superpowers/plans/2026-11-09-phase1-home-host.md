# Phase 1 Home Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document and wire Docker Compose plus an optional Cloudflare Tunnel so sideloaded phones can reach a Mac on a home network.

**Architecture:** Compose already has db+server. Optional profile `tunnel` runs cloudflared. README is the runbook. No Azure.

**Tech Stack:** Docker Compose, cloudflared, Xcode sideload.


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

Modify: `docker-compose.yml`, `README.md`, `server/.env.example`
Create: `ios/Support/GPX/riverside.gpx`, `docs/superpowers/plans/2026-11-09-mvp-playtest.md`

### Task 1: Compose tunnel profile and runbook

cloudflared service profile `tunnel`, command `tunnel --no-autoupdate run --token ${TUNNEL_TOKEN}` OR quick tunnel `tunnel --url http://server:8000`. Never commit TUNNEL_TOKEN.

README sections: start (`docker compose up`), caffeinate, named vs quick tunnel, paste URL into the app, sideload (Xcode, trust cert), health check `curl https://<host>/v1/healthz`.

- [ ] **Step 1:** Add compose profile and README
- [ ] **Step 2:** `docker compose config` succeeds
- [ ] **Step 3:** Commit `docs: add home-host and sideload runbook`

### Task 2: GPX fixture for simulator

Create `ios/Support/GPX/riverside.gpx` looping around Prospect Park sample coordinates. Document in playtest note: Xcode > Simulate Location. Human park game is out of band.

Commit: `test: add GPX route for simulator playtest`
