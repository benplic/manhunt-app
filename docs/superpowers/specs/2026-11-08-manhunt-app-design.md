# Manhunt App - Design Spec

- **Date:** 2026-11-08
- **Status:** Approved design, pending spec review
- **Audience:** Friends first, architected so it can go public on the App Store later

## 1. Goal

An iOS app for playing real-world Manhunt with friends: the host configures hiders/seekers,
a map area, safe zones, and out-of-bounds zones; the app handles precise location, verified
tagging, timed location reveals, a points economy with power-ups, and safety alerts. The
architecture must make new rules, power-ups, and game modes cheap to add.

## 2. Decisions Summary

| Topic | Decision |
|---|---|
| Client platform | Native iOS (Swift / SwiftUI). Backend stays platform-neutral so Android can be added later. |
| Tagging | Ultra Wideband (Nearby Interaction) proximity verification; rotating signed QR code fallback for devices without UWB. |
| Location reveals | Periodic fuzzy reveals (host sets interval and fuzz radius) plus optional hot/cold distance/direction hints. |
| Out of bounds | Accuracy-aware detection, warning, host-set countdown, then host-chosen penalty. |
| Safe zones | Untaggable inside; per-visit time limit; disabled by Lockdown power-up. |
| Host setup | In the iOS app for v1. Arenas and presets are server-side objects so a web editor can be added later. |
| Backend | Python FastAPI + WebSockets, server-authoritative, on Azure Container Apps; PostgreSQL + PostGIS; IaC in Bicep. |
| Auth | Sign in with Apple only. |
| Extensibility | Game modes are compositions of rule modules with lifecycle hooks; modules publish versioned settings schemas. |

## 3. Architecture

Three deployable components:

1. **iOS app (SwiftUI).** MapKit (map, zone drawing), Core Location (foreground + background
   updates during a game), Nearby Interaction (UWB ranging), AVFoundation (QR scanning).
   Screens: Sign-in, Lobby/Join, Arena Editor, Preset Editor, Live Game, Results.
   The app is a thin client: it sends location updates and action requests and renders
   server-pushed state. It never decides game outcomes.
2. **Game server (FastAPI).**
   - REST: accounts, arenas, presets, create/join game (6-character join code), host actions.
   - WebSocket (one per player per game): live location in, game events out.
   - Each active game is an in-memory `GameSession` with a 1-second tick loop driving timers,
     reveals, countdowns, and power-up durations.
   - Zone checks run in memory with Shapely against the game's arena snapshot.
3. **PostgreSQL + PostGIS (Azure Database for PostgreSQL Flexible Server).** Persistent storage
   for users, arenas, presets, games, players, and the append-only game event log.

Push notifications (APNs) for invites and "game starting."

## 4. Extensibility Model

### 4.1 Rule modules

A **game mode** is a named composition of **rule modules**. Each module implements any subset
of these hooks:

- `on_start(session)`
- `on_tick(session, now)`
- `on_location(session, player, reading)`
- `on_tag(session, tag_claim)`
- `on_zone_enter(session, player, zone)` / `on_zone_exit(session, player, zone)`
- `on_event(session, event)` (generic listener, used by the points economy)
- `check_win(session) -> WinResult | None`

Modules may also **modify** other modules' behavior through a shared effects system
(for example, Ghost marks a player as excluded from the next reveal; the reveal module checks
active effects). Effects have an owner, target, type, and expiry.

Built-in v1 modules:

| Module | Responsibility | Key settings |
|---|---|---|
| Role assignment | Assign hiders/seekers | random with counts or ratio, manual, volunteer; re-roll |
| Head start | Hiders hide before seekers are released | duration; seeker lock mode (spawn zone or locked map) |
| Reveal: periodic fuzzy | Show hiders' approximate positions to seekers | interval, display duration, fuzz radius |
| Reveal: hot/cold | Distance/direction hints toward hiders | enabled, update frequency, granularity |
| Tag policy | Validate tags and apply results | method (UWB/QR), tag radius (default 2 m), result (eliminate or convert to seeker) |
| Zone policy | Out-of-bounds and safe-zone enforcement | OOB countdown (default 15 s), OOB penalty (auto-tag or forced reveal), safe-zone time limit per visit, safe-zone re-entry cooldown |
| Signal-loss safety | Going-dark detection and alerts | silence threshold, penalty threshold, penalty type |
| Points economy | Award points for events | per-rule point values and thresholds |
| Power-ups | Purchasable effects | per-power-up enabled, cost, duration, cooldown |
| Win condition | End the game | all hiders caught, time limit, or both |

"Classic Manhunt" is a built-in preset combining these modules with default settings.

### 4.2 Settings schemas

Each module publishes a **versioned settings schema** (JSON Schema subset: number with
min/max/step, boolean, enum, duration). The iOS app renders preset settings forms generically
from these schemas, so new modules and options usually do not require an App Store update.
A preset stores `{module_id, module_version, settings}` per module. The server validates
presets against the schema and migrates older settings versions when loading.

### 4.3 Event log

Every state change is an event appended to `game_events` with a per-game sequence number.
The event log powers reconnect catch-up, crash recovery (replay to rebuild the session),
dispute resolution, and future replays and stats.

## 5. Live Game Flow

### 5.1 Phases

`Lobby -> HeadStart -> Active -> Ended` (with `Paused` available to the host from HeadStart or Active).

### 5.2 Location

- High-accuracy Core Location updates every 2-3 s or every 3 m, whichever comes first.
- Background updates use the `location` background mode with **When In Use** authorization
  (blue status-bar indicator). The app never requests Always authorization.
- Each reading includes `horizontalAccuracy`. Readings worse than 30 m are used for display
  only and never for zone or proximity decisions.
- Joining a game requires location permission with Precise Location enabled. The app explains
  and links to Settings otherwise.

### 5.3 Zones

- A player is **out of bounds** only when outside the play area (or inside an OOB zone) by more
  than `horizontalAccuracy + margin` (margin default 5 m).
- OOB state machine: `Inside -> Warning (haptic + banner) -> Countdown (host-set, default 15 s)
  -> Penalty`. Returning inside during Warning or Countdown resets to Inside.
- **Safe zones:** players inside cannot be tagged. A per-visit timer runs. On expiry the player
  is notified and is taggable even if still inside until they leave and the zone's cooldown
  passes. The Lockdown power-up disables all safe zones for its duration.

### 5.4 Going dark (safety and anti-cheat)

- If the server receives no location for the **silence threshold** (host setting), the player is
  marked `signal_lost` and **all players are alerted**.
- The player's **last known precise location** (with timestamp and accuracy radius) is shown to
  **all players regardless of team or game rules**. Safety overrides gameplay.
- The app sends a flagged precise "low battery" ping at 5% battery, and a best-effort final
  ping when location is disabled or the app is terminating. iOS does not guarantee the final
  ping, so the server's last-known location is the real safety net.
- After the longer **penalty threshold**, the host-configured penalty applies. The safety alert
  persists until the player reconnects or the host acknowledges it.

### 5.5 Tagging: Ultra Wideband

1. When a seeker and a hider are within ~30 m by GPS, the server relays Nearby Interaction
   discovery tokens so their phones can start a UWB ranging session.
2. The seeker sees nearby hiders with live UWB distances.
3. The seeker taps **Tag**. The claim is sent with the seeker's measured distance.
4. The server requests the hider's own measurement and accepts the tag only if both are within
   the tag radius and the hider is not shielded or protected by an active safe zone.
5. The tag policy applies the result. Rejections return a specific reason code.

Nearby Interaction limits concurrent sessions per device. The server keeps sessions only with
each player's closest opponents, capped at the limit. **To verify during implementation:**
the exact concurrent-session limit on current iOS.

### 5.6 Tagging: QR fallback

For devices without UWB (pre-iPhone 11) or when ranging fails: the hider's screen shows a QR
code containing a server-signed token (HMAC, signing key in Key Vault) that rotates every 30 s.
The seeker scans it, and the server validates signature, expiry, game, and target eligibility.

### 5.7 Reconnects

The client reconnects with exponential backoff and sends the last sequence number it received.
The server replays missed events or sends a full state snapshot if the gap is large.

## 6. Points Economy and Power-ups

### 6.1 Earning points

| Rule | Who | Trigger (defaults, all host-configurable) |
|---|---|---|
| Close call | Hider | A seeker is within 15 m (accuracy-adjusted) for at least 5 s, then the hider gets back beyond 30 m without being tagged |
| Survival | Hider | Every N minutes survived while active |
| Taunt | Hider | Voluntarily broadcast precise location to seekers for N seconds. Points scale with nearest-seeker distance at taunt time, so taunting from far away earns little. |
| Others tagged | Surviving hiders | Every time N other hiders are tagged |
| Tag | Seeker | Each successful tag |

Close-call detection is GPS-based (UWB sessions exist only between already-paired phones), so
thresholds are conservative to avoid awarding points for GPS jitter.

### 6.2 Power-ups (v1)

All host-toggleable, each with cost, duration, and cooldown.

| Power-up | Team | Effect |
|---|---|---|
| Ghost | Hider | Hidden from the next periodic reveal |
| Decoy | Hider | Next reveal shows a fake pin at a chosen location (must be inside the play area) |
| Radar | Hider | See seekers' locations for 20 s |
| Jammer | Hider | Seekers' hot/cold hints disabled for N minutes |
| Shield | Hider | Cannot be tagged for 30 s |
| Scan | Seeker | Immediate fuzzy reveal of one random active hider |
| Tracker | Seeker | Hot/cold hints toward the nearest hider for N minutes |
| Lockdown | Seeker | Safe zones disabled for N minutes |

Purchases and activations are server-validated (balance, cooldown, phase, role) and logged.

## 7. Host Setup

- **Create game:** pick or draw an arena, pick a preset (Classic or saved), adjust settings,
  share join code / QR / invite link.
- **Lobby:** players join, host assigns roles (randomize with counts and re-roll, manual, or
  volunteer), then starts.
- **In-game host controls:** pause/resume, end game, remove player, undo a tag (logged).
- **Arena editor:** tap to place polygon points and drag to adjust; circle tool for safe zones.
  Zone types: one play-area boundary, any number of safe zones, any number of OOB zones, and an
  optional seeker spawn zone (used by the head-start module).
  Validation: no self-intersection, all other zones must lie inside the play area.
- Games store **snapshots** of the arena and preset at creation, so later edits never affect a
  running game.

## 8. Data Model

| Table | Key fields |
|---|---|
| `users` | id, apple_sub (unique), display_name, created_at |
| `arenas` | id, owner_id, name, boundary (geography polygon), version, updated_at |
| `arena_zones` | id, arena_id, type (`safe` / `out_of_bounds` / `seeker_spawn`), name, geometry (geography) |
| `rule_presets` | id, owner_id, name, mode_id, modules (JSONB: module_id, module_version, settings), schema_version |
| `games` | id, join_code, host_id, status, arena_snapshot (JSONB), preset_snapshot (JSONB), created_at, started_at, ended_at |
| `game_players` | game_id, user_id, role, status, points, inventory (JSONB) |
| `game_events` | game_id, seq, type, payload (JSONB), created_at. Primary key (game_id, seq). |

## 9. Security and Privacy

- **Authentication:** Sign in with Apple; server verifies Apple identity tokens and issues
  short-lived session tokens. WebSocket connections authenticate with the session token.
- **Authorization:** every action is checked server-side against game membership, role,
  phase, and host status.
- **Input validation:** Pydantic models for all REST and WebSocket messages. Coordinates
  range-checked, and geometry validated and size-limited (max vertices per polygon).
- **Rate limiting:** per-connection limits on location updates and actions.
- **Secrets:** Apple sign-in key, APNs key, QR signing key, and the field-encryption key live in
  Azure Key Vault, accessed by managed identity. No secrets in the repo.
- **Location as PII:**
  - Precise location fields in `game_events` are encrypted at the field level (key in Key Vault).
  - Precise location trails are deleted automatically 7 days after a game ends (host-adjustable).
    Outcomes and coarse events are retained.
  - All reads of precise location trails are logged.
- **Anti-cheat:** server-authoritative state, dual-sided UWB distance confirmation, rotating
  signed QR tokens, signal-loss detection. GPS spoofing on iOS is hard but possible. v1 accepts
  that risk for a friends group.

## 10. Error Handling and Reliability

- **Client:** reconnecting banner with backoff; clear blocking screens for missing location
  permission or Precise Location disabled; server error codes mapped to user-facing messages.
- **Server:** invalid actions return typed error codes (for example `TARGET_SHIELDED`,
  `INSUFFICIENT_POINTS`, `NOT_IN_RANGE`). Unexpected exceptions are logged with game and player
  context and never crash the session loop.
- **Crash recovery:** on startup the server rebuilds active games by replaying their event logs.
- **Deploys:** wait until no games are active.

## 11. Testing Strategy

- **Server unit tests (pytest):** every rule module and power-up, with an injectable fake clock
  for deterministic timers.
- **Geometry tests:** points on boundaries, concave polygons, tiny zones, accuracy-margin edge
  cases.
- **Bot simulation harness:** scripted bot players follow GPS paths over real WebSockets and
  play full games end to end. This is the primary integration test.
- **iOS:** XCTest for view models; Xcode GPX routes for simulated movement. UWB tested on
  physical devices only (two iPhone 11 or newer).

## 12. Deployment

- **Azure (Bicep):** Container Apps (one always-on replica in v1), PostgreSQL Flexible Server
  with PostGIS enabled, Key Vault, Container Registry, Application Insights / Log Analytics.
- **CI/CD (GitHub Actions):** tests on every push; automatic deploy to dev; production deploy
  gated by a manual approval environment.
- **iOS distribution:** TestFlight (requires the Apple Developer Program, $99/year).
- **Scale-out (deferred):** Redis pub/sub plus game-affinity routing when more than one replica
  is needed.

## 13. Milestones (v1)

1. **Server engine:** session loop, rule modules, event log, REST/WebSocket APIs, bot simulation.
2. **iOS core:** sign-in, lobby, live map, location reporting, basic arena editor, zones and OOB,
   QR tagging, going-dark safety alerts.
3. **UWB and reveals:** Nearby Interaction tagging, periodic fuzzy reveals, hot/cold hints.
4. **Economy:** points rules and all eight power-ups.
5. **Polish:** schema-driven preset editor, full arena editor, results screen.

## 14. Out of Scope for v1

Web host editor, Android client, replay viewer and stats, additional game modes, a "jail" tag
result (needs jail zones and a release mechanic), and public-launch
requirements (moderation and reporting, age gating, full privacy policy, multi-replica scale-out).
