# Remaining benchmarks

Source of truth for unfinished work: [2026-11-09-manhunt-roadmap.md](2026-11-09-manhunt-roadmap.md). This file is the gap list. A phase in the roadmap is not done until every bullet here that cites it is closed.

Branch at the time this was written: `cursor/manhunt-mvp-2a9d` at `2866303`. Current branch: `main` at `04b0c15`. Server tests: 81 passed. iOS tests: 47 passed on iPhone 16 Pro, iOS 18.4. The local API may be running on `http://localhost:8000` with SQLite because Docker socket access was denied. Do not treat that process as the home-host gate.

## Already in the repo

Phase 0, Phase 1 engine (1.1–1.8), most of the Phase 1 API and iOS client, the home-host runbook, and partial Phase 2–5 code (refresh tokens, AES-GCM helper, input replay, host undo/remove, hot/cold bands, UWB radius check, points, eight power-ups, module schema endpoint, saved presets, invite URL, results timeline, Bicep draft, TestFlight workflow stub). Do not rebuild those. Close the gaps below.

## Open

Each item is open until the acceptance line is true. Human items stay open until a person does them.

### Phase 1

- **1.24 Home-host gate (human).** Acceptance: `curl https://<tunnel>/v1/healthz` returns 200 from a phone on cellular, and a sideloaded Debug build signs in against that URL.
- **MVP playtest gate (human).** GPX file exists at `ios/Support/GPX/riverside.gpx`. Acceptance: a simulator run using that GPX, then three sideloaded phones in a park, covering join, head start, a reveal, a hider out-of-bounds elimination, a seeker out-of-bounds pin visible to hiders, a QR tag, and a going-dark alert. Checklist: [2026-11-09-mvp-playtest.md](2026-11-09-mvp-playtest.md).

### Phase 2

- **2.0 Azure, for real.** Code: GHCR image, `minReplicas` 0 / `maxReplicas` 1, B1ms Postgres, Key Vault secrets plus system identity, deploy wait on `/v1/readyz`, “Waking the hunt server…”, 15 s self-ping while a game is live. Acceptance still needs a human: `prod` environment reviewers, first `workflow_dispatch`, and verifying the self-ping on real ACA. Do not treat a shared environment as shippable until 2.4’s test is green (it is).
- **2.1 Sign in with Apple.** The app presents Sign in with Apple and posts `identity_token` to `/v1/auth/apple` (`testSignInWithAppleHitsTheFake`). `aud` is `app.manhunt.ios`. Dev auth stays off in `azure`/`prod`. Still open until the paid Apple team is attached to `app.manhunt.ios`.
- **2.8 APNs.** Start and invite record notifications (`test_start_and_invite_record_notifications`). HTTP/2 send runs when the Key Vault `.p8` is set. Still open until a phone receives “game starting” and invite pushes. Needs the paid Apple team and a key that is not in the repo.
- **2.9 App Insights.** Bicep creates an Insights component on the 1 GB/day Log Analytics workspace and injects `APPLICATIONINSIGHTS_CONNECTION_STRING`. Deploy waits on `/v1/readyz`. Still open until a human deploy shows the resource in the portal.

### Phase 3

- **3.1 Device ranging (human).** The relay and the phone ranger are in. Still open until two iPhone 11 or newer, in the same place, confirm a tag and measure `NIError.Code.activeSessionsLimitExceeded`. The code cap stays 5 until that measurement (`UWB_MAX_PEERS`, `NearbyUWBRanger.maxPeers`).

### Phase 5

- **5.6 TestFlight (human).** `.github/workflows/testflight.yml` archives with manual signing and uploads with `xcrun altool` when the `prod` environment has `BUILD_CERTIFICATE_BASE64`, `BUILD_PROVISION_PROFILE_BASE64`, `P12_PASSWORD`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY`. Acceptance: a human with the signing credentials runs that workflow and the build appears in TestFlight. Stays open until that person does it.

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
- **2.3 Trail retention.** `4c913e5`, `test_purge_deletes_sensitive_events_older_than_retention`, `test_host_trail_read_writes_audit_without_logging_coordinates`. Acceptance: a scheduled purge deletes sensitive events older than 7 days (host-adjustable via `MANHUNT_TRAIL_RETENTION_DAYS`), and every read of a decrypted trail writes an audit-log row. Coordinates still never appear in logs.
- **2.4 Crash recovery.** `4c913e5`, `test_restart_rebuilds_mid_game_phase_roles_points_and_locations`. Acceptance: kill the process mid-game, start it again, and the rebuilt session matches the pre-crash phase, roles, points, and last precise locations.
- **2.5 Phone-side safety pings.** `4c913e5`, `testLocationFlagSendsLowBatteryOncePerDipAndFinalWins`, `testLowBatteryThenEndSendsFinalFlag`. Acceptance: the app sends `low_battery` at about 5% and a best-effort final ping when the game is backgrounded or ended.
- **3.1 Nearby Interaction relay.** `539de80`, `6e6c1ae`, `test_ten_meters_opposite_roles_exchange_tokens`, `test_forty_meters_apart_yields_no_peers`, `test_cap_keeps_the_closest_opponents`, `test_relay_tag_ignores_a_forged_range_and_drops_a_non_peer`, `test_relay_tag_rejects_nan_and_infinite_ranges`, `testRepublishesDiscoveryTokenAfterReconnect`. Acceptance: the server relays discovery tokens only when GPS distance is at most 30 m, and only with each player’s closest opponents. Record the concurrent-session limit for the iOS version under test in a code comment. The comment records Apple’s unpublished cap and the temporary limit of 5. A two-phone measurement stays open above.
- **3.3 Hint dock.** `539de80`, `test_hint_bearing_due_north_is_zero`, `test_hint_holds_until_the_interval_elapses`, `test_jammer_clears_the_hint_on_the_next_tick`, `testHintLineShowsBandMetersAndBearing`, `testClearedHintSaysNoneYet`. Acceptance: the dock shows band and bearing at the module’s update rate, and a jammer clears it.
- **3.4 Spawn lock on the phone.** `539de80`, `test_spawn_zone_lock_banners_a_seeker_who_leaves`, `test_seeker_inside_the_spawn_zone_is_not_locked_out`, `test_locked_map_has_no_spawn_lock`, `testHeadStartChrome`. Acceptance: the live map shows that lock while `seeker_lock` is `spawn_zone`.

### 2026-11-10

- **4.6 Power-up dock.** `88a1312`, `c40c459`, `a07f7ff`. Acceptance: chips are enabled or greyed out with `PowerUpRules` before the request is sent, Decoy asks for a point inside the play area, and Radar shows seeker pins only while the effect is active. `is_decoy` stays off the wire. Tests: `test_cooldowns_ride_on_you_only`, `testDecoyChipIsTappableWhenOnlyNeedsTarget`, `testRadarSeekersFollowEffectsNotLocalToggle`, `testOutsideDecoyKeepsPickingAndSurfacesTheNote`.
- **5.2 Schema-driven preset editor.** `8673e6e`, `testSchemaFormRoundTripsASavedPreset`, `testSavedPresetRoundTripsThroughTheService`. Acceptance: the editor is generated from `GET /v1/modules`, and saved presets round-trip through `rule_presets`.
- **5.3 Arena editor.** `8673e6e`, `testPlayAreaDropSplitsTheSelectedEdge`, `testDragRenameAndDeleteVertex`. Acceptance: the player selects an edge and drops a point that splits that edge, so a new vertex cannot create an hourglass. Drag, rename, and delete are supported. Self-intersection is still rejected on save.
- **5.4 Results timeline depth.** `8673e6e`, `test_results_timeline_includes_playtest_events_in_order`, `testTimelineSortsThePlaytestEventsBySeq`. Acceptance: the timeline is the ordered non-sensitive event log for that game, including reveal, out of bounds, tag, and signal loss.
- **5.5 Invite link and QR join.** `8673e6e`, `testUniversalLinkAndInviteQRBothJoin`. Acceptance: a universal link and a QR code both join the game. The association file is `GET /.well-known/apple-app-site-association`.
- **Leave game (client).** `30bdcdb`, `testLeaveClearsTheMatchAndHitsTheService`. Acceptance: lobby/live X calls `POST /v1/games/{id}/leave`, disconnects the socket, clears the match, and returns home so quiet lobbies stop the 15 s self-ping.
- **Host controls (client).** `30bdcdb`, `testRemoveLobbyPlayerHitsTheService`, `test_undo_tag_restores_the_hider`. Acceptance: host can undo the last tag, acknowledge safety, end (plus pause/resume), and remove a non-host lobby player via existing routes.
- **Taunt (client).** `30bdcdb`, `testTauntDuringActiveRaisesPoints`. Acceptance: hiders in the active phase can taunt from the live dock; wrong role/phase surfaces a denial note; points bump on success.
- **UWB → QR fallback.** `30bdcdb`, `test_uwb_preset_still_accepts_qr_with_pairing`, `testUwbMethodStillOffersQrScanFallback`. Acceptance: a valid `qr_token` claim is accepted under `method == "uwb"` after GPS pairing; dual-range stays required for UWB-only claims. Live seeker chrome keeps Scan / Show tag code as the fallback.
- **Refresh token + soft errors + APNs client hook.** `30bdcdb`, `testRefreshRotatesTheFakeToken`, `testPendingDeviceTokenRegistersAfterAuth`. Acceptance: refresh tokens persist in Keychain; a 401 triggers one `POST /v1/auth/refresh` then retry (auth paths excluded); failed refresh signs out. WS send failures and location stream drops surface on the reconnecting/note banner. A pending APNs device token is `PUT /v1/me/device-token` after auth (Push entitlement remains a human gate).
