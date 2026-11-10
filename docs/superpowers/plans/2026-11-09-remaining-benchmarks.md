# Remaining benchmarks

Source of truth for unfinished work: [2026-11-09-manhunt-roadmap.md](2026-11-09-manhunt-roadmap.md). This file is the gap list. A phase in the roadmap is not done until every bullet here that cites it is closed.

Branch at the time this was written: `cursor/manhunt-mvp-2a9d` at `2866303`. Server tests: 51 passed. iOS tests: 18 passed. The local API may be running on `http://localhost:8000` with SQLite because Docker socket access was denied. Do not treat that process as the home-host gate.

## Already in the repo

Phase 0, Phase 1 engine (1.1–1.8), most of the Phase 1 API and iOS client, the home-host runbook, and partial Phase 2–5 code (refresh tokens, AES-GCM helper, input replay, host undo/remove, hot/cold bands, UWB radius check, points, eight power-ups, module schema endpoint, saved presets, invite URL, results timeline, Bicep draft, TestFlight workflow stub). Do not rebuild those. Close the gaps below.

## Open

Each item is open until the acceptance line is true. Human items stay open until a person does them.

### Phase 1

- **1.24 Home-host gate (human).** Acceptance: `curl https://<tunnel>/v1/healthz` returns 200 from a phone on cellular, and a sideloaded Debug build signs in against that URL.
- **MVP playtest gate (human).** GPX file exists at `ios/Support/GPX/riverside.gpx`. Acceptance: a simulator run using that GPX, then three sideloaded phones in a park, covering join, head start, a reveal, a hider out-of-bounds elimination, a seeker out-of-bounds pin visible to hiders, a QR tag, and a going-dark alert. Checklist: [2026-11-09-mvp-playtest.md](2026-11-09-mvp-playtest.md).

### Phase 2

- **2.0 Azure, for real.** Bicep is a draft and has not been deployed. Acceptance: `deploy.yml` is `workflow_dispatch`, the `prod` environment requires reviewers, the image comes from GHCR, Container Apps `minReplicas` is 0 and `maxReplicas` is 1, Postgres B1ms stays on, Key Vault holds the signing keys, and a deploy waits until `/v1/readyz` reports no active games. The iOS client shows “Waking the hunt server…” and retries the first request for up to 60 seconds. While any game is `lobby`, `head_start`, `active`, or `paused`, the process does not rely on a quiet WebSocket alone to stay up (self-ping or an equivalent that is verified on ACA).
- **2.1 Sign in with Apple.** The server can verify an Apple identity token. The app still uses display-name dev auth. Acceptance: the app presents Sign in with Apple, `aud` is `app.manhunt.ios`, and dev auth stays off when `MANHUNT_ENV` is `azure` or `prod`. Needs the paid Apple team.
- **2.3 Trail retention.** Encrypt and decrypt exist. Acceptance: a scheduled purge deletes sensitive events older than 7 days (host-adjustable), and every read of a decrypted trail writes an audit-log row. Coordinates still never appear in logs.
- **2.4 Crash recovery.** Startup replays `games.inputs`, not the event log named in the roadmap. Acceptance: kill the process mid-game, start it again, and the rebuilt session matches the pre-crash phase, roles, points, and last precise locations. Do not turn on scale-to-zero for a shared environment before this test passes.
- **2.5 Phone-side safety pings.** The server handles `low_battery` and `final` location flags and host safety ack. Acceptance: the app sends `low_battery` at about 5% and a best-effort final ping when the game is backgrounded or ended.
- **2.8 APNs.** `server/app/notify.py` records notifications in memory. Acceptance: “game starting” and invites are delivered through APNs. Needs the paid Apple team and a key that is not in the repo.
- **2.9 App Insights.** Log Analytics has a 1 GB/day cap in Bicep. Acceptance: App Insights is wired with that cap, and `/v1/readyz` is what deploy waits on.

### Phase 3

- **3.1 Nearby Interaction relay.** Not started. Acceptance: the server relays discovery tokens only when GPS distance is at most 30 m, and only with each player’s closest opponents. Record the concurrent-session limit for the iOS version under test in a code comment.
- **3.3 Hint dock.** Hot/cold is a distance band on the server and one line of copy on the phone. Acceptance: the dock shows band and bearing at the module’s update rate, and a jammer clears it.
- **3.4 Spawn lock on the phone.** The server banners a seeker who leaves the spawn zone. Acceptance: the live map shows that lock while `seeker_lock` is `spawn_zone`.

### Phase 4

- **4.6 Power-up dock.** Chips call purchase. Acceptance: chips are enabled or greyed out with `PowerUpRules` before the request is sent, Decoy asks for a point inside the play area, and Radar shows seeker pins only while the effect is active. `is_decoy` stays off the wire.

### Phase 5

- **5.2 Schema-driven preset editor.** `GET /v1/modules` exists. The form is still hand-built. Acceptance: the editor is generated from that schema, and saved presets round-trip through `rule_presets`.
- **5.3 Arena editor.** Drawing appends vertices and can bowtie. Self-intersection is rejected on save. Acceptance: the player selects an edge and drops a point that splits that edge, so a new vertex cannot create an hourglass. Also support drag, rename, and delete. This replaces the older “drag vertices only” note in the roadmap.
- **5.4 Results timeline depth.** The results screen lists event text. Acceptance: the timeline is the ordered non-sensitive event log for that game, including the events the playtest cares about (reveal, out of bounds, tag, signal loss).
- **5.5 Invite link and QR join.** The API returns a URL string. Acceptance: a universal link and a QR code both join the game.
- **5.6 TestFlight.** `.github/workflows/testflight.yml` archives with signing off and does not upload. Acceptance: a human with the signing credentials can archive and upload to TestFlight from that workflow.

## How to close an item

1. Read the roadmap bullet and the acceptance line above.
2. Add or extend a test that fails first, except for items marked human.
3. Implement only that item.
4. Run `pytest -q` and `ruff check .` in `server/`, and the iOS `xcodebuild test` command in the roadmap worker playbook, when the change touches that side.
5. Move the item from Open to a dated “Closed” note at the bottom of this file, with the commit hash and the test name. Do not delete the acceptance line.
6. Do not mark a parent phase done while any of its items are still open.

## Closed

### 2026-11-09

- **1.9 Alembic and join-code uniqueness.** `a483703`, `test_live_join_code_is_unique_and_reusable_after_end`. Acceptance: an initial migration creates the tables, and a partial unique index allows reuse of a join code only after the game is `ended` or `abandoned`. A test inserts two live games with the same code and fails.
- **1.12 Join rate limit.** `244de91`, `test_eleventh_join_in_a_minute_is_rate_limited` (window edge: `test_join_window_forgets_attempts_older_than_a_minute`). Acceptance: the eleventh `POST /v1/games/join` from one user inside a minute returns 429 `RATE_LIMITED`.
- **1.15 Debug-only arbitrary HTTP.** `ef841db`. Release product `Info.plist` has `NSAllowsLocalNetworking` and no `NSAllowsArbitraryLoads` (`xcodebuild build -configuration Release`). Debug product keeps both, because ATS cannot follow a runtime `http://` LAN URL. Acceptance: Release does not allow arbitrary loads. Debug allows local networking, and allows arbitrary loads only when that is still required for a non-loopback `http://` home server.
- **1.19 Live lobby.** `83963de`, `test_join_and_roles_push_a_lobby_view`. Acceptance: after create or join, the lobby updates from the WebSocket `view` (a second phone joining changes the list without a manual refresh).
- **1.20 Settings link.** `ef841db`, `testSettingsLinkOpensTheAppSettingsPage`. iOS suite: 19 tests passed on iPhone 16 Pro, iOS 18.4. Acceptance: the banner button opens the app’s Settings page. The app still never requests Always.
