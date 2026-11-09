# Phase 0 Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the FastAPI package, make GameRulesTests compile and pass, and add GitHub Actions CI.

**Architecture:** A thin FastAPI app with healthz plus a startup guard for dev auth. iOS domain types live under ios/Manhunt/Domain and Editor. CI runs pytest and xcodebuild test.

**Tech Stack:** Python 3.12+, FastAPI, pydantic-settings, pytest, ruff, httpx. Swift 5, iOS 18, XCTest. GitHub Actions.


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

- Create: `server/pyproject.toml`, `server/app/__init__.py`, `server/app/main.py`, `server/app/config.py`, `server/app/errors.py`, `server/app/logging_setup.py`, `server/.env.example`, `server/Dockerfile`, `docker-compose.yml`, `server/tests/__init__.py`, `server/tests/conftest.py`, `server/tests/test_health.py`, `server/tests/test_dev_auth_guard.py`
- Create iOS Domain files listed below
- Delete: `ios/ManhuntTests/PreviewMatchTests.swift`, `ios/ManhuntTests/AppStoreTests.swift` (rewritten in Phase 1 iOS)
- Create: `.github/workflows/ci.yml`

### Task 1: Server scaffold and healthz

**Files:**
- Create: `server/pyproject.toml`, `server/app/main.py`, `server/app/config.py`, `server/app/errors.py`, `server/app/logging_setup.py`, `server/tests/test_health.py`, `server/tests/test_dev_auth_guard.py`, `server/.env.example`, `server/Dockerfile`, `docker-compose.yml`

**Interfaces:**
- Consumes: nothing
- Produces: `create_app() -> FastAPI`, `Settings` with `manhunt_env`, `manhunt_dev_auth`, `validate_startup()`, `ErrorCode` enum, `GET /healthz` and `GET /v1/healthz` both return `{"status":"ok"}`

- [ ] **Step 1: Write the failing tests**

```python
# server/tests/test_health.py
from fastapi.testclient import TestClient
from app.main import create_app

def test_healthz_ok():
    client = TestClient(create_app())
    for path in ("/healthz", "/v1/healthz"):
        response = client.get(path)
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
```

```python
# server/tests/test_dev_auth_guard.py
import pytest
from app.config import Settings, DevAuthMisconfigured

@pytest.mark.parametrize("env", ["azure", "prod"])
def test_dev_auth_refused_in_cloud_envs(env):
    settings = Settings(manhunt_env=env, manhunt_dev_auth=True, manhunt_session_signing_key="x"*32, manhunt_qr_signing_key="y"*32)
    with pytest.raises(DevAuthMisconfigured):
        settings.validate_startup()

@pytest.mark.parametrize("env", ["local", "test", "home"])
def test_dev_auth_allowed_for_mvp(env):
    settings = Settings(manhunt_env=env, manhunt_dev_auth=True, manhunt_session_signing_key="x"*32, manhunt_qr_signing_key="y"*32)
    settings.validate_startup()
```

- [ ] **Step 2: Run tests, expect FAIL** (`ModuleNotFoundError` / `create_app` missing)

Run: `cd server && python3 -m venv .venv && . .venv/bin/activate && pip install -e '.[dev]' && pytest -q`
Expected: FAIL collecting tests

- [ ] **Step 3: Write minimal implementation**

`pyproject.toml` requires python>=3.12, deps: fastapi, uvicorn[standard], pydantic-settings, sqlalchemy[asyncio], psycopg[binary], alembic, shapely, pyjwt[crypto], httpx, websockets. Dev: pytest, pytest-asyncio, ruff.

`Settings` fields (env prefix none, names as env vars): MANHUNT_ENV default local, MANHUNT_DATABASE_URL default `postgresql+psycopg://manhunt:manhunt@127.0.0.1:5432/manhunt`, MANHUNT_SESSION_SIGNING_KEY, MANHUNT_QR_SIGNING_KEY, MANHUNT_APPLE_AUDIENCE default `app.manhunt.ios`, MANHUNT_DEV_AUTH default false, MANHUNT_TICK_LOOP default true.

`ErrorCode` is a str Enum with every code from Contracts.

`create_app` registers exception handlers that return `{"error":{"code","message","details"}}`.

Dockerfile: `python:3.13-slim`, workdir /app, pip install, CMD uvicorn app.main:app --host 0.0.0.0 --port 8000. Compose: db postgres:16 with POSTGRES_USER/PASSWORD/DB=manhunt, port 5432, healthcheck; server build `./server`, env MANHUNT_ENV=home, MANHUNT_DEV_AUTH=true, depends_on db healthy; server-test profile that runs pytest.

- [ ] **Step 4: pytest -q and ruff check . pass**
- [ ] **Step 5: Commit** `feat: scaffold FastAPI app with healthz and dev-auth guard`

### Task 2: iOS domain core

**Files:**
- Create: `ios/Manhunt/Domain/*.swift`, `ios/Manhunt/Editor/ArenaEditorModel.swift`
- Delete: `ios/ManhuntTests/PreviewMatchTests.swift`, `ios/ManhuntTests/AppStoreTests.swift`

**Interfaces:** match `GameRulesTests.swift` and `Fixtures.swift` exactly. Names in the Swift domain API section of the roadmap.

- [ ] **Step 1: Existing tests are the failing tests.** `GameRulesTests` already exists.
- [ ] **Step 2: Run** `cd ios && xcodebuild test -project Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`
Expected: FAIL, types missing
- [ ] **Step 3: Implement types until all GameRulesTests pass.**

`GeoPoint`: Codable keys lat/lon, Equatable, Hashable.
`JoinCode`: alphabet excluding 0,O,1,I,L. normalize trims+uppercases. isValid is 6 chars all in alphabet. generate picks 6 using RandomNumberGenerator.
`SplitMix64`: RandomNumberGenerator, splitmix64 algorithm, `init(state: UInt64)`.
`ArenaGeometry.meters`: 111_320 * hypot(dlat, dlon * cos(lat0)).
`contains`: polygon covers point, boundary counts as inside.
`isConfidentlyOutside`: false if accuracyMeters > 30; else true when distance-to-polygon > accuracyMeters + marginMeters.
`ArenaValidator`: playAreaTooSmall if < 3 vertices; selfIntersection if edges cross; outsidePlayArea if a zone is not covered by the play area.
`BoundsMachine.receive(isOutside:countdownSeconds:)`: inside; first outside -> warning; second consecutive outside -> countdown(N); further outside decrement; 0 -> penalized; any inside resets to inside. Stay penalized until inside.
`RoleAssigner.assign`: empty -> empty; hiderCount clamped to [0, count]; shuffle with RNG; first N hiders rest seekers.
`PowerUpRules.decide`: check in order insufficientPoints, coolingDown, wrongPhase (must be active), wrongRole, eliminated, needsTarget.
`ArenaEditorModel`: Observable, not MainActor. tool EditorTool. addMapPoint: playArea appends vertex; safeCircle first tap stores center, second commits circle zone; outOfBounds/seekerSpawn append polygon vertices to current zone of that kind or start a new one. undo pops last action. issues from ArenaValidator.

- [ ] **Step 4: xcodebuild test PASS**
- [ ] **Step 5: Commit** `feat: add iOS domain types so GameRulesTests pass`

### Task 3: GitHub Actions CI

**Files:** Create `.github/workflows/ci.yml`

- [ ] **Step 1:** workflow with jobs `server` (ubuntu-latest, python 3.13, postgres:16 service, pip install -e .[dev], ruff, pytest) and `ios` (macos-15, xcodebuild test same destination).
- [ ] **Step 2:** Commit `ci: run server pytest and iOS tests on push`
