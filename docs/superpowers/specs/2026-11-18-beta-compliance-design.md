# External beta compliance design

- **Date:** 2026-11-18
- **Status:** Approved design
- **Scope:** External TestFlight-style beta (not full App Store release). Full audit findings from `/review-compliance`, except Sign in with Apple and other Apple Developer Program / App Store Connect–only work (separate plan).
- **Also:** Remove ping sound and ping flashlight flash.

## 1. Goal

Make the iOS client + server ready for an external beta against Apple App Review Guidelines that bind TestFlight (Guideline 2.2), without waiting on a working Sign in with Apple flow.

Ship:

1. In-app privacy policy (Critical).
2. In-app account deletion (Critical).
3. Age field next to name; under 13 blocked with a clear message; privacy policy + App Store age rating (rating questionnaire is Apple-only).
4. Display-name filter + report + per-device block.
5. Fixed cloud base URL in Release (testers do not type a server URL); Play + home key remain.
6. Privacy manifest for UserDefaults; location/camera purpose strings; physical-harm safety copy; contact mailto; home key in Keychain; export-compliance flag.
7. Remove ping light and ping audio (manual flashlight stays).

Defer to `docs/superpowers/plans/2026-11-18-apple-developer-account.md`: Sign in with Apple, App Store Connect metadata (privacy URL field, Support URL, nutrition labels, age rating answers), TestFlight upload / Beta App Review notes, push entitlement, ASC export prompts.

## 2. Decisions (locked)

| Topic | Choice |
|---|---|
| Beta auth before SIWA | Fixed cloud `MANHUNT_API_BASE_URL`; Play + home key; hide typed Server URL in Release |
| Privacy policy | Short in-repo policy + public HTTPS page; in-app links on Sign-in, Home, Account |
| Account deletion | Hard delete personal data on confirm; anonymize game memberships; sign out client |
| Display names | Reserved-word filter + report (mailto) + block (hide pin/name for this device) |
| Age | Integer age next to name on sign-in; `<13` blocked client + server; App Store rating in Apple plan |
| SIWA button | Hide until Apple plan wires entitlement + audience |
| Ping alerts | Delete sound + torch-on-ping entirely; keep manual flashlight |
| Approach | One repo compliance pack; one Apple Program plan |

## 3. Architecture

### 3.1 Account & Safety surface

New lightweight Account screen (reachable from Home) owns:

- Link to privacy policy (Safari / in-app browser).
- Contact / support mailto.
- Delete account (confirm → API → clear keychain → signed-out).
- Entry point copy for safety (or safety shown once before first live hunt).

Sign-in gains: **Age** field next to **Display name**, privacy link, no SIWA button, no Server URL in Release builds.

### 3.2 Privacy policy

- Source of truth: `docs/legal/privacy.md` (committed).
- Publish as HTTPS (GitHub Pages on this repo, or a domain the host already owns). Exact host is a human step; the app uses one build-time / Info.plist URL key `ManhuntPrivacyPolicyURL`.
- Policy must cover: display name; age; precise location (gameplay, background during an open hunt, who can see pins under game rules including safety overrides); installation id / home auth; optional APNs device token; retention (sensitive location purge, default 7 days); account deletion; no ads / no tracking SDKs; contact email.

### 3.3 Account deletion

- `DELETE /v1/me` (authenticated).
- Server: revoke refresh tokens; delete device token; delete owned arenas and rule presets; anonymize `display_name` on related game player rows / live session if present; delete `users` row (or equivalent hard removal of personal record).
- Game history rows may remain with anonymized names so join-code history does not crash; no personal identifiers left on the user record.
- Client: call delete → `signOut()` clearing tokens → stay on sign-in.

### 3.4 Age gate

- Client: required integer age on sign-in (next to name). Persist last accepted age locally for the install.
- `POST /v1/auth/dev` body includes `age: int`. If `age < 13`, return `403` with a stable error code (e.g. `TOO_YOUNG`) and message that Manhunt is not available under 13.
- Join / create do not re-collect age; gate is at account creation / Play.
- Under-13 never receives tokens.

### 3.5 Names: filter, report, block

- **Filter:** shared blocked-token list (profanity / hate slurs — keep list short and maintainable). Reject on client before Play; server re-checks `display_name` on `/v1/auth/dev` and any rename path.
- **Report:** from lobby / live player chrome → mailto with subject/body including `game_id`, `player_id`, display name, reporter install context. Uses the same support address as Contact.
- **Block:** per-device `Set` of blocked `player_id` UUIDs in Keychain or UserDefaults. Map / player lists hide blocked players’ pins and names for the local user only. Unblock on Account or player menu later if cheap; minimum is block for beta.

### 3.6 Fixed cloud base URL

- Release `MANHUNT_API_BASE_URL` build setting points at the cloud / named-tunnel HTTPS origin (not localhost).
- Sign-in **Server URL** field is Debug-only (`#if DEBUG` or Info-Debug-only UX).
- Home key remains; stored in Keychain (not UserDefaults).
- Debug builds keep typed URL + arbitrary HTTP loads as today.

### 3.7 Purpose strings & manifests

- Update `NSLocationWhenInUseUsageDescription` to state gameplay uses, that other players can see your location under the game’s rules, and that location stays active for an open hunt (including when the phone is locked during that hunt). Still When In Use only; no Always string.
- Update `NSCameraUsageDescription` for QR tag scanning; mention manual flashlight only if that control remains (it does).
- Add `PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults` with approved reason `CA92.1`.
- Set `ITSAppUsesNonExemptEncryption` = `false` in Release `Info.plist`.

### 3.8 Safety copy (physical harm)

Before the first live hunt on an install (or every hunt if persistence is annoying to build — prefer once): short modal — play only where legal and safe; you are responsible for your surroundings; not for reckless use on public roads. Does not change rules engine.

### 3.9 Remove ping sound / ping torch

Delete:

- Ping settings gear + `PingAlertSettingsSheet`
- `pingSoundEnabled` / `pingFlashlightEnabled` state, AppSettings keys, `handlePingAlerts` sound/torch path
- `PingSound` usage from AppStore (file may remain unused or be deleted if nothing else needs it)
- Related unit tests

Keep: manual flashlight button; visual ping pulse / haptics if already separate from sound.

### 3.10 Contact

Support mailto on Account and reachable from report. Address is an Info.plist / build setting `ManhuntSupportEmail` so it is not hard-coded in five views.

## 4. Out of scope (Apple plan)

- Sign in with Apple entitlement, capability, audience ↔ bundle id
- Showing the SIWA button again
- App Store Connect privacy URL, Support URL, nutrition labels, age rating questionnaire
- TestFlight archive upload and Beta App Review notes (demo home key, cloud URL)
- APNs push entitlement wiring
- Any statute-specific COPPA/GDPR legal opinion beyond the age gate and policy text

## 5. Testing

- Server: auth rejects age &lt; 13; rejects blocked names; `DELETE /v1/me` removes user and tokens; surviving game rows show anonymized name.
- iOS: Sign-in shows age, hides server URL in Release configuration tests where practical; deletion signs out; block hides a player in map/list helpers; ping alert tests removed or inverted to assert no sound/torch on ping; privacy/support URLs present on Account.

## 6. Docs to update after implement

- `README.md` — Release base URL, home key, privacy URL publish step, age gate.
- Design out-of-scope line in `2026-11-08-manhunt-app-design.md` that deferred privacy / moderation — note beta subset shipped.
