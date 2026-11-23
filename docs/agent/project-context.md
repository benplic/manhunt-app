# Manhunt project context

Working picture of the product for agents. Read this file, then `docs/agent/agent-learnings.md`, before planning, editing, or asking Scott a question.

This file is not a second roadmap. It records what the running tree is, which older docs have drifted, and product facts Scott states in chat that are not written down anywhere else.

## How to keep it true

- If code and this file disagree, trust the code, then fix this file in the same change.
- If Scott states a product fact in chat and it is not already in the repo, append it under [Heard in conversation](#heard-in-conversation) before the turn ends. Date it in America/New_York. Do not put testing or programming lessons there.
- Do not copy secrets, coordinates, tokens, or trail payloads into this file.
- Do not mark a benchmark done here. Done-ness lives only in `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md`.

## What the product is

Manhunt is a real-world game for friends. Hiders run, seekers hunt, inside a park the host draws. Phones report location. A FastAPI server decides every outcome. Clients render a per-player view. They do not decide tags, wins, or zone penalties.

Audience is friends first. Ranked play with strangers is last on the horizon and is not open.

Playable clients today:

- `ios/` — SwiftUI app. Home sideload (Debug, server URL on the sign-in screen) and a Release build whose API origin is compiled in (`https://manhunt.pivotlattice.app`).
- `web/` — Vite + React client for friends who cannot sideload. Hosted on Cloudflare Pages (`https://manhunt-app.pages.dev`). It is a play client, not an arena or preset editor.
- `server/` — authoritative game server. Home host is Docker Compose plus a Cloudflare Tunnel. Azure Bicep exists and is not a finished human deploy.

Privacy pages stay on GitHub Pages (`docs/legal/privacy` → `benplic.github.io/manhunt-app`). Do not host the game there.

## Architecture

```
iOS (SwiftUI)  ─┐
                ├─ REST + one WebSocket per player ─► FastAPI
Web (React)    ─┘                                      │
                                                       ├─ GameSession in memory, 1s tick
                                                       ├─ build_view() filters what that player may see
                                                       └─ Postgres: accounts, arenas, games, event log
```

Three rules sit under that picture:

1. The server is the only rules engine. iOS `FakeGameService` and web helpers may grey out a button or reject an obvious client mistake. They must not become a second engine that can disagree with the server.
2. Every outbound game state goes through `server/app/engine/views.py::build_view`. There is no "send the session" path.
3. `server/app/engine/` is pure. It does not import FastAPI, asyncio, or the database. Time comes from `Clock`. Randomness comes from `random.Random(seed)` on the session. `datetime.now()` and the global `random` module stay outside the engine (`realtime/clock.py`, auth, purge, join-code generation).

A game is a composition of rule modules (`server/app/engine/modules/`). `GameSession` builds one instance per preset entry. An unknown module id is skipped (`cls is None: continue`). A typo in a preset silently drops that rule. Do not add a module id that is not in `MODULE_TYPES`.

Phases: `lobby` → `head_start` → `active` → `ended`. `paused` is reachable from `head_start` or `active`. Pause freezes `game_elapsed_s`. Signal-loss still ticks during pause, on the injected clock, because going dark is safety. While a seeker spawn lock holds the head-start clock, `head_start`, `zone_policy`, and `signal_loss` still tick, and win is still checked.

Timers that are rules count **game seconds**. Wall-clock silence uses `clock.now()`, which tests replace with `FakeClock`.

## Visibility (the anti-cheat boundary)

`build_view` is the filter. Seekers must not receive a hider's precise fix except where a rule below says so.

Who sees a location after the lobby (lobby locations are omitted):

- You always see yourself exactly.
- Same role sees teammates exactly. Unassigned players are not teammates.
- `signal_lost`: last precise fix goes to everyone, `kind: "last_known"`. Safety overrides the hunt.
- A seeker with `oob_revealed` is shown exactly to every player until they are back inside. A hider who is out of bounds is not revealed this way. Hiders are on the auto-tag path.
- A hider with radar active sees seeker fixes exactly, for that hider only.
- A hider who is taunting is shown exactly until the taunt window ends.
- After `ended`, last fixes are shown. A player still `signal_lost` stays `last_known`.

Also true of the current view, and easy to "clean up" into a bug:

- `is_decoy` never appears in the serialized view. `tests/engine/test_views.py` asserts the string is absent. Decoy pins ride in `reveals` without a decoy flag.
- Jammer and taunt are not public attributed effects. Public timed effects are `shield` and `lockdown` only. Radar and tracker stay on `you.effects`.
- `points` and `points_earned` are currently on every player row, not only on `you`. The Nov 9 contract snippet is older. Do not move them unless a task says so.
- `converted_from_hider` is on every player row so a hider can pick a Rescue target.
- `avatar_url` is always null. Photo upload is not shipped.
- Safe zones are stripped from `arena` in the view while lockdown has turned them off.
- Demo payload is omitted when the viewer is not allowed to see controls. Demo routes stay off when `MANHUNT_ENV` is `azure` or `prod` unless explicitly overridden.

Readings with `accuracy_m > 30` (`ACCURACY_CUTOFF_M`) are for display only. Zone, tag, reveal, points, and head-start decisions ignore them. The web client uses the same cutoff.

## Geometry

Distances use a flat projection: **111,320 meters per degree**, longitude scaled by `cos(lat0)`. Not haversine. The Swift geometry test expects 111.32 m; haversine yields 111.19 m.

Polygon containment includes the boundary (`Shapely.covers`). There is no PostGIS in this version. Arena geometry is JSON and is checked in memory.

Arena limits enforced with the validator: 3 to 100 vertices, at most 30 zones, latitude in [-90, 90], longitude in [-180, 180], circle radius 2 to 500 m. Other zones must lie inside the play area. Self-intersection is rejected. Games store snapshots of the arena and preset at creation.

Out of bounds is role-specific. A player is confidently outside only when the distance past the boundary is greater than `accuracy_m + margin` (margin default 5 m) and accuracy is within the 30 m cutoff. Hiders: warning, then countdown (default 15 s), then `auto_tag` (eliminated). Seekers: exact pin to everyone while outside, not auto-tagged. The warning still tells them to return.

## Tags, win, and names

Tag method in the classic preset is `qr`. Ultra Wideband and Nearby Interaction were removed on 2026-11-18 (playtest 2). Do not put them back. A QR claim still needs a GPS pairing check (default 30 m) plus signature, expiry, game, role, and active status. The hider token rotates about every 30 seconds.

`WinModule` treats only `status == "eliminated"` as caught. `signal_lost` is still in the game. Seekers do not win because a hider went dark. The signal-loss module can eliminate a hider later, only when its `penalty` setting is `eliminate` and `penalty_after` has elapsed. Classic default penalty is `none`. An API host that still counts `signal_lost` as a tag ends the hunt early with "All hiders were tagged." The web README calls that out. Confirm the deployed server before blaming a client.

Classic role assignment is `seeker_count` (default 1, range 1 to 20). `GameSession.assign_roles_random` takes a seeker count. `assign_hiders_random` exists only to replay inputs logged before that change. The Nov 9 roadmap still says `hider_count`. The code is the contract.

Start requires both a hider and a seeker (`NEED_BOTH_ROLES`). Player cap is 20 (`GAME_FULL`).

Join codes are 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no I, L, O, 0, 1), shared by `server/app/games/join_code.py`, `ios/Manhunt/Domain/JoinCode.swift`, and `web/src/api/joinCode.ts`. `PARK42` is reserved for the sample lobby. A live join code is unique; it may be reused after the game is `ended` or `abandoned`. The eleventh join from one user inside a minute is `RATE_LIMITED`.

Display name: trimmed, collapsed whitespace, 1 to 40 characters. The blocklist tokens in `server/app/auth/names.py` and `ios/Manhunt/Domain/DisplayNameRules.swift` must match. The server returns `NAME_BLOCKED`. The sign-in field starts empty. `Casey` is a test fixture name, not a product default. Do not prefill it.

Age under 13 is `TOO_YOUNG` on the server and both clients. Required for external beta, not only for an App Store rating.

Error codes are the `ErrorCode` enum in `server/app/errors.py`, mirrored case-for-case in `ios/Manhunt/Domain/ErrorCode.swift`. Add a code in both places in the same change. The HTTP body is `{"error":{"code","message","details"}}`. The Nov 9 roadmap list is missing codes that shipped later (`DISPLAY_NAME_TAKEN`, `REMATCH_NOT_READY`, `TOO_YOUNG`, `NAME_BLOCKED`).

## Clients

### iOS

`AppStore` is `@MainActor` and `@Observable`. Socket callbacks hop back to the main actor. `ArenaEditorModel` is `@Observable` and is **not** `@MainActor`. `GameRulesTests` call it from a nonisolated context. Putting it on the main actor breaks those tests.

Screens: `signedOut`, `home`, `createGame`, `lobby`, `live`, `results`, `arenaEditor`, `preset`.

iOS 18, Swift 5, no Swift packages. Sources under `ios/Manhunt/` and `ios/ManhuntTests/` are synchronized folders. Add a file by putting it in the folder. Do not add file references to `project.pbxproj`. Edit that file only for a build setting a task names.

The app never requests Always location. When In Use, precise location, during a game. Background updates use the location background mode.

Debug shows Server URL and may allow local and arbitrary HTTP so a tunnel-less LAN host works. Release hides Server URL, bakes `MANHUNT_API_BASE_URL`, and does not allow arbitrary loads. Home key (`MANHUNT_DEV_AUTH_SECRET`) is stored in the Keychain. Sign in with Apple stays hidden until the paid Apple team is on `app.manhunt.ios`.

### Web

Thin React UI over the same REST and WebSocket `PlayerView`. Live map is Leaflet. QR scan uses `html5-qrcode` because iOS Safari has no `BarcodeDetector`.

Create posts a fresh 400 m circle arena and a classic game. There is no web arena editor and no demo panel. No Sign in with Apple, push, flashlight, haptics, or background GPS.

Location is watched only while the tab is visible. Safari can suspend GPS when the screen locks. Desk testing heartbeats a steady fix and ignores a reading worse than ±30 m or a teleport jump.

Access token, refresh token, and home key live in `localStorage`. The origin is trusted. XSS can read the party secret. That is an accepted MVP limit, not a pattern to copy into iOS.

`MANHUNT_CORS_ORIGINS` on the API must include the Pages origin or the browser client cannot call the host.

## Server shape

| Area | Path | Job |
|---|---|---|
| Composition root | `server/app/main.py` | App, lifespan, crash recovery, routes |
| Settings | `server/app/config.py` | Env, startup guards |
| Engine | `server/app/engine/` | Pure rules, views, QR, recovery |
| Modules | `server/app/engine/modules/` | roles, head_start, reveal_fuzzy, tag_policy, zone_policy, zone_shrink, signal_loss, win, effects, points, power_ups, hot_cold |
| HTTP games | `server/app/games/` | Create, join, roles, tags, host actions |
| Realtime | `server/app/realtime/` | WebSocket, tick loop, fan-out |
| Auth | `server/app/auth/` | Dev sign-in, Apple stub, tokens, account delete |
| Demo | `server/app/demo/` | PARK42 bots and host controls |

Startup refuses to boot when:

- `MANHUNT_DEV_AUTH` is true and `MANHUNT_ENV` is `azure` or `prod`.
- `MANHUNT_ENV` is `home`, `azure`, or `prod` and a signing key, the trail key, or the database URL is still a known default, or the home key is shorter than 16 characters while dev auth is on.

Demo controls default on for `local`, `test`, and `home`, and off for `azure` and `prod`.

Crash recovery replays logged inputs through the deterministic engine (seed + logged clock). `test_restart_rebuilds_mid_game_phase_roles_points_and_locations` is the gate. Do not treat a shared Azure environment as shippable on scale-to-zero until a human has done the 2.0 deploy checks. Bicep still has `minReplicas: 0`.

Precise location in the event log is field-encrypted. Trail retention default is 7 days. A trail read writes an audit row. Logs never contain coordinates or tokens.

WebSocket: client sends `hello` (token, optional `last_seq`) then `location` and `ping`. Server sends `welcome`, a full `view`, then non-sensitive `event`s with `seq` greater than `last_seq`. Sensitive events are not replayed on that catch-up. Close codes: 4401 unauthorized, 4403 not a member, 4404 no game, 4429 rate limited.

## What is already in the tree

Phase 0 and the Phase 1 engine are in the tree. Do not rebuild them.

Also present, and not a reason to re-implement: home-host runbook, refresh tokens, trail encryption and purge, crash recovery, host undo/remove, hot/cold, points, power-ups (the original eight plus Rescue, Create safe, Move safe, Shrink now), module schemas, saved presets, invite link, results timeline, zone shrink, demo lobby, account deletion, age gate, web friend client.

The design spec (`docs/superpowers/specs/2026-11-08-manhunt-app-design.md`) and the roadmap contracts (`docs/superpowers/plans/2026-11-09-manhunt-roadmap.md`) describe the v1 intent. Where they still mention UWB, PostGIS, `hider_count`, or a shorter `ErrorCode` list, the code has moved. Do not "restore" the older contract.

Plan frontmatter can be stale. The 2026-11-20 web friend-parity plan still shows tasks pending in its YAML. That YAML is not the gap list. Read the code and the remaining-benchmarks file.

## What is still open

Source of truth: `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md`, Open section, as read on 2026-11-23. Re-read it. This paragraph goes stale when that file changes.

Human gates, still open until a person does them:

- 1.24 cellular tunnel health check and a sideloaded Debug sign-in.
- MVP park playtest (join, head start, reveal, hider out-of-bounds elimination, seeker out-of-bounds pin, QR tag, going-dark alert).
- 2.0 Azure: reviewers, first `workflow_dispatch`, self-ping on real Container Apps.
- 2.1 Sign in with Apple, after the paid team is on `app.manhunt.ios`.
- 2.8 A phone actually receives the APNs "game starting" and invite pushes.
- 2.9 App Insights resource visible in the portal after a human deploy.
- 5.6 TestFlight upload by a human with the signing credentials.

Horizon, in this order, and not started until Scott opens one:

1. Capture the flag
2. Senior assassin
3. Long-distance persistent games
4. Ranked / public lobbies

## Which document to open

| Question | Open |
|---|---|
| Is this bullet done? | `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md` |
| What did we intend to build, and in what order? | `docs/superpowers/plans/2026-11-09-manhunt-roadmap.md` |
| Original product rules | `docs/superpowers/specs/2026-11-08-manhunt-app-design.md` |
| How do I run a home game? | `README.md` |
| How does the browser client differ? | `web/README.md` |
| What must every agent obey? | `AGENTS.md`, then this file and `docs/agent/agent-learnings.md` |
| What does the server actually do? | `server/app/engine/` and `server/app/errors.py` |

## Heard in conversation

Product facts Scott states in chat that are not already in the repo. Testing and programming lessons do not go here.

None yet. The 2026-11-23 request that created this file set the agent process, which is recorded in `docs/agent/agent-learnings.md`. It did not add a product requirement.

## Not settled

The repo does not say what to build next. Human gates above are waiting on a person. Horizon modes stay closed until Scott opens one. Do not pick a horizon mode, a new rule, or a public-launch feature to fill the gap.
