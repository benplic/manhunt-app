# Demo Lobby (PARK42): Moving Bots, Bot Tagging, and Demo Controls

- **Date:** 2026-11-12
- **Status:** Approved design
- **Branch:** `cursor/demo-lobby-bots-controls-49cc` (off `cursor/live-hud-circle-arena-c733`)

## 1. Goal

Turn the `PARK42` solo sample lobby into a self-contained, playable demonstration of Manhunt's live rules from any location:

- Five server-driven bots move inside the sample park, stay alive (do not go dark unintentionally), and exercise safe zones, out-of-bounds countdowns, reveals, hot/cold hints, zone shrink, and seeker-on-hider tagging.
- When another seeker is in the game (either a bot seeker alongside a human player, or a second seeker), seeker bots actively chase and tag active hiders through the real engine `claim_tag` pipeline.
- The human host has virtual map-tap movement (phone GPS is ignored in demo games so the demo works indoors from any city) plus a host-only Demo Controls panel to adjust speed, skip time, force tags, switch teams, advance phases, force reveals, trigger going-dark and out-of-bounds alerts, and add points.

## 2. Architecture & Decisions

### 2.1 Server-side simulation in the real engine

Bots and demo actions execute directly against `GameSession` in a new `server/app/demo/` package (`state.py`, `bots.py`, `controls.py`, `routes.py`), leaving `FakeGameService` on iOS purely for unit/UI tests.

- **Synthetic locations (`GameSession.set_synthetic_location`).** Bots and virtual human steps update `player.location`, `player.last_precise`, `player.last_location_at`, `player.battery`, and run `module.on_location(...)`, **without** appending to `event_log` or `state.inputs`. `record_location` would append an event and an input per bot per tick and rewrite the entire `inputs` JSON blob on every tick.
- **Restart policy.** Because synthetic locations are not written to `inputs`, replaying a bot tag during crash recovery would fail with `NOT_IN_PAIRING_RANGE`. On server startup in `main.py`, sample games (`join_code == SAMPLE_CODE`) in `lobby`, `head_start`, `active`, or `paused` are marked `abandoned` rather than rebuilt (with a `TODO:` for future snapshot-based demo recovery).
- **Determinism & geo rules.** `BotDriver` uses a seeded `random.Random` initialized from `session.state.seed` (never the global `random`), computes all distances and offsets through `app.engine.geo` (`111,320 m/degree`), and reads `session.clock.now()` (never `datetime.now()`).

### 2.2 Circle sample arena & preset

`_sample_arena()` in `server/app/games/service.py` defines a circle arena centered on the Riverside Green park centroid (`40.6617, -73.9690`, `radius_m = 210.0`, `boundary_circle` populated plus 64-vertex `boundary` ring) containing:

- One **seeker spawn** polygon (`ZoneKind.SEEKER_SPAWN`) near the south/center of the circle.
- One **safe** circle (`ZoneKind.SAFE`, `radius_m = 25`) inside the northern half.
- One **out-of-bounds** polygon (`ZoneKind.OUT_OF_BOUNDS`) inside the eastern edge.

`_create_sample` initializes `classic_preset` with overrides:
- `zone_shrink`: `{"enabled": True, "every": 1, "shrink_to": 75, "min_radius_m": 60}` so the `LiveHUD` zone timer and `ZoneShrinkModule` fire visibly every minute.
- `head_start`: `{"enabled": True, "duration": 60, "seeker_lock": "spawn_zone"}` (toggleable in the lobby between `spawn_zone` and `locked_map`).

When `GameService._create_sample` registers the session, `session.demo = DemoState.initial(session)` is attached and bots + host receive initial inside-arena positions so every player appears on the map immediately when the hunt starts.

### 2.3 Bot behavior (`server/app/demo/bots.py`)

`BotDriver.step(session)` runs after each engine tick when `session.demo` is present:

- **Non-demo / non-bot players:** If the human host has a `human_target` set, `BotDriver` walks the human up to `walk_speed_mps` (default `5.0 m/s`) toward `human_target` and clears the target on arrival; otherwise refreshes the human's synthetic fix at their current position so they do not silently go dark while idle (unless the host explicitly puts them dark).
- **Bot modes (`DemoBotMode`):**
  - `auto`: normal AI behavior.
  - `go_dark`: skips updating `last_location_at` (and stops refreshing fixes) so `SignalLossModule` transitions the bot to `signal_lost` after `silence` seconds and triggers the safety banner.
  - `oob`: steers the bot outside the current play boundary (or into the no-go zone) to trigger the out-of-bounds countdown, hider elimination, and OOB seeker reveal pin.
- **Head start:**
  - Bot seekers stay inside the `SEEKER_SPAWN` zone (or near center if no spawn zone exists) while `phase == "head_start"`.
  - Bot hiders wander away from the spawn zone inside `session.state.arena.boundary` (never caching the boundary across ticks, because `zone_shrink` shrinks it).
- **Active phase:**
  - **Bot hiders:** wander at ~`2.8 m/s`, flee away from any visible/nearby seeker within `70 m`, and steer strongly inward whenever within `12 m` of or outside the current play boundary (or inside an out-of-bounds zone).
  - **Bot seekers:** patrol inside the play area at ~`3.2 m/s`, chase the nearest active hider (within `60 m`, or any active reveal pin / taunting hider) at ~`4.2 m/s`, and when within `tag_policy.radius_m` (`<= 2 m`) and after a brief per-match tag cooldown (`tag_cooldown_s`, initial 10 s after head start ends and 8 s between bot tags so a demo does not finish instantaneously), call `session.claim_tag(TagClaim(seeker_id, hider_id, seeker_range=0.5, hider_range=0.5, qr_token=...))` using a freshly signed QR token when `method == "qr"` or dual `0.5 m` ranges when `method == "uwb"`.
  - If `claim_tag` raises `GameRuleError` (for example `TARGET_IN_SAFE_ZONE` or `TARGET_SHIELDED`), the seeker treats it as a miss and keeps wandering for a short backoff without crashing the tick loop.

### 2.4 Tick speed, lobby hold, and WebSocket isolation

- **`SessionManager.tick_all`:** For a session with `session.demo` in `head_start` or `active`, runs `session.demo.speed` iterations of `session.tick()` followed by `BotDriver.step(session)`. Speed is clamped to `{1, 2, 5, 10}`. Note: wall-clock timers (`signal_loss` and QR token TTL) advance in real time rather than scaling with `demo.speed`; `go_dark` therefore backdates `last_location_at` directly.
- **Lobby countdown hold:** `_advance_sample` skips decrementing `sample_waited_s` while `session.demo.lobby_hold` is `True`.
- **WebSocket isolation (`ws.py`):** When `session.demo is not None`, incoming client `location` messages are ignored so real phone coordinates never displace the virtual dot into Brooklyn out-of-bounds.

### 2.5 Demo API (`POST /v1/games/{game_id}/demo`) and view payload

- **Feature gate:** `Settings.manhunt_demo_controls: bool | None = None` in `server/app/config.py`. Effective value defaults to `True` when `manhunt_env in {"local", "test", "home"}` and `False` when `manhunt_env in {"azure", "prod"}` unless explicitly overridden.
- **Authorization:** Returns `404 GAME_NOT_FOUND` if demo controls are disabled or `session.demo is None`. Requires membership; all actions except `move_me` require `is_host` (`403 NOT_HOST` otherwise).
- **Actions:**
  - `set_speed` (`speed`: 1 | 2 | 5 | 10)
  - `skip` (`seconds`: 1..600, default 60) — runs `N` tick+bot steps immediately (stopping early if the game ends)
  - `force_tag` (`hider_id` optional) — picks `you` if hider, else nearest active hider; places nearest seeker `0.5 m` away and calls real `claim_tag` (so safe zones and shields still apply and surface real `GameRuleError`s)
  - `switch_team` (`role`: `"hider"` | `"seeker"` optional toggle) — switches caller role mid-game (or lobby), restores `active` status, clears stale safe/oob flags
  - `end_phase` — in `lobby`: starts match immediately; in `head_start`: ticks remaining head start seconds to enter `active`; in `active` / `paused`: ends the match
  - `force_reveal` — sets `last_reveal_at_s` so the next tick (or immediate tick) emits reveals
  - `add_points` (`amount`: 1..1000, default 100) — adds points to caller
  - `bot_go_dark` (`bot_id` optional, `dark`: bool) — sets bot mode to `go_dark` and backdates `last_location_at` beyond `silence`, or restores bot to `auto` with a fresh fix
  - `bot_oob` (`bot_id` optional, `oob`: bool) — sets bot mode to `oob` (walks outside boundary) or restores to `auto`
  - `move_me` (`lat`, `lon` finite coordinates) — sets `demo.human_target` and walks caller immediately a step toward target (or snaps inside play area if caller had no location yet)
  - `lobby_hold` (`hold`: bool) — pauses/resumes the 30 s sample lobby auto-start countdown
  - `set_seeker_lock` (`mode`: `"spawn_zone"` | `"locked_map"`) — updates `head_start.seeker_lock` in `lobby`
- **Logging:** Demo route logs only `action` and `game_id`; coordinates and tokens are never logged.
- **View (`build_view`):** When `session.demo is not None`, adds `"demo"` to the view JSON:
  ```json
  {
    "speed": 1,
    "lobby_hold": false,
    "seeker_lock": "spawn_zone",
    "controls_enabled": true,
    "virtual_location": {"lat": 40.6617, "lon": -73.9690},
    "bots": [
      {"player_id": "...", "display_name": "Riley Chen", "role": "hider", "status": "active", "mode": "auto"}
    ]
  }
  ```
  `controls_enabled` is `True` only when `manhunt_demo_controls` is enabled and `viewer.is_host` is `True`. `is_decoy` and secret bot internals are never exposed.

## 3. iOS Client (`ios/Manhunt`)

- **`DTOs.swift`:** Add optional `DemoDTO` (`speed`, `lobbyHold`, `seekerLock`, `controlsEnabled`, `virtualLocation`, `bots`) on `PlayerViewDTO` so non-demo games decode `nil` cleanly.
- **`GameService` / `LiveGameService` / `FakeGameService`:** Add `demo(gameID: UUID, action: String, params: [String: RuleValue]) async throws -> PlayerViewDTO` hitting `POST /v1/games/{id}/demo`.
- **`AppStore`:**
  - Suppress `location.start()` and `sendFix(...)` when `match?.snapshot.demo != nil`.
  - Add `demoPicking` map-drop mode (mutually exclusive with `decoyPicking`) using `HuntMap.onDrop` to dispatch `move_me`.
  - Expose clean helpers (`setDemoSpeed`, `demoSkipMinute`, `demoForceTag`, `demoSwitchTeam`, `demoEndPhase`, `demoForceReveal`, `demoAddPoints`, `demoToggleBotDark`, `demoToggleBotOOB`, `demoMoveMe`, `demoToggleLobbyHold`, `demoSetSeekerLock`).
- **`LiveGameView` & `DemoPanelView`:**
  - Show a compact `Demo` chip in `LiveGameView.topBar` when `snapshot?.demo?.controlsEnabled == true` (alongside the existing host controls button).
  - `DemoPanelView` sheet uses the dark circular/pill visual language (`HuntColor.ink`, `HuntColor.inkRaised`, `HuntColor.signal`, `HuntColor.seeker`) to present speed selector (`1x`, `2x`, `5x`, `10x`), phase/time actions (`Skip 1 min`, `End phase`), gameplay actions (`Force tag`, `Switch team`, `Force reveal`, `+100 pts`, `Move me`), and bot toggles (`Go dark / Restore`, `Send OOB / Return`).
- **`LobbyView`:** When `snapshot?.demo?.controlsEnabled == true` (or `lobbyStartsInS != nil`), display a Demo Lobby card with `Start now`, `Hold / Resume countdown`, `My team` toggle (`Hider` / `Seeker`), and `Seeker lock` picker (`Spawn zone` / `Locked map`).

## 4. Verification Plan

- **Server (`server/tests/demo/` & `server/tests/sim/`):**
  - Determinism (same seed produces identical bot coordinates).
  - Bots stay inside shrinking circle boundaries (`ZoneShrinkModule` + `BotDriver`).
  - Seeker bots chase and tag active hiders; `TARGET_IN_SAFE_ZONE` does not crash and lets bots continue wandering.
  - Synthetic bot fixes do not append `inputs` or sensitive `event_log` rows.
  - All 12 `POST /v1/games/{id}/demo` actions work and enforce host/demo/config gates (`403 NOT_HOST`, `404` on normal games, `404` when `manhunt_env="prod"`).
  - WebSocket `location` messages from humans are ignored in demo sessions.
  - Lifespan startup marks leftover live sample games `abandoned` rather than failing replay.
  - Full demo simulation test in `tests/sim/test_demo_game.py` verifying a demo match plays through head start, shrink, reveal, and seeker bot tags to a seeker win.
- **iOS (`ios/ManhuntTests/DemoControlsTests.swift`):**
  - Decoding `PlayerViewDTO` with and without `demo`.
  - `AppStore` demo actions against `FakeGameService`, `move_me` pick mode, and GPS suppression when `demo != nil`.
