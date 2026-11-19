# Manhunt Privacy Policy

*Effective date: 2026-11-19. Last updated: 2026-11-19.*  
*Draft for external beta.*

## Who we are

Manhunt is a location-based outdoor game operated for beta testing. This policy describes what we collect, how we use it, and your choices. Questions: **support@manhunt.pivotlattice.app**.

## Data we collect

- **Display name** — stored on your server user record and shown to other players in your games. You can change it by signing in again with a new name (subject to our name rules).
- **Age** — collected at sign-in as a **self-reported** whole number to enforce a minimum age of **13**. We check it when you sign in (app and server). We store it **only on your device** (for example `manhunt.ageYears`); we do **not** persist age on your server user record. We do not independently verify age beyond this gate.
- **Precise location** — while a hunt is open, to enforce the play area, safe zones, tags, and in-game safety features. Sent to our server and shared with other players in that game under the game rules. Accuracy depends on your device, GPS, and environment; safety features are aids, not guarantees.
- **Installation identifier** — a stable id for this app (or browser) install, used to authenticate and restore your session.
- **Home auth secret** — the party “home key,” stored **only on your device** (iOS Keychain, or browser storage on the web client) to restore sign-in; we do not log this value.
- **Account metadata on the server** — typically: user id, display name, auth handle (dev install handle and/or Apple subject when enabled), account creation time, refresh-token records, optional push device token, owned arenas and rule presets, and game membership rows (game id, role/status, join time). Gameplay may also create game records, encrypted location-related inputs, and event-log rows (some marked sensitive).
- **Optional push notification token** — if notifications are enabled and the build supports them, we store an Apple Push Notification service (APNs) device token to send game-related alerts.

We do not use advertising SDKs, cross-app tracking, or third-party analytics/crash-reporting SDKs in the beta clients.

## Age 13+ and underage accounts

Manhunt is intended for users **13 and older**. Sign-in is blocked when the self-reported age is under 13. If we learn that an account belongs to someone under 13 (for example via a report or support request), we will delete that account and associated personal data as described under **Account deletion**, and you should email **support@manhunt.pivotlattice.app**. Parents or guardians who believe a child under 13 created an account should contact us at the same address.

Depending on where beta testers live, additional youth-privacy rules may apply. This beta relies on a self-attested age gate rather than government ID or credit-card age verification.

## How location is shared with other players

During an open hunt, players in the same game can see positions and related gameplay state as defined by that hunt’s rules (including safety alerts where enabled). **Leaving a hunt or ending the hunt stops broadcasting your live coordinates** to other players in that game; the client also stops sending location updates when you leave or return home. Manhunt on iOS requests **When In Use** location only; it does not ask for Always location access. On the web client, location is used while the page is allowed to access geolocation (typically while the tab is open).

**Outdoor play is at your own discretion.** Stay aware of traffic, terrain, weather, and local rules. In-app safety banners and alerts depend on connectivity and GPS conditions and may be delayed or unavailable.

### Safety, reporting, and blocking

- You can **leave** a lobby or live hunt from the app at any time.
- You can **report** another player by email (mailto) with game and player identifiers for moderation.
- You can **block** a player on your device: they stay in the hunt, but their name is shown as an anonymized label (for example “Blocked Player #1”) and their pin remains; when chat exists, blocked players’ messages will be hidden on your device.
- Safety acknowledgements may be stored on your device and/or reflected in gameplay state. We do **not** currently keep a separate long-term “incident report” database inside the game beyond normal gameplay logs and any email you send to support.

## Retention

- **Sensitive location trails** (encrypted location-related inputs used for gameplay forensics) are purged on a rolling basis with a default **7-day** maximum retention (`MANHUNT_TRAIL_RETENTION_DAYS`, default 7), unless a shorter window is configured on the host.
- **Non-sensitive gameplay event text** (for example tags or announcements that are not marked sensitive) may remain associated with a game until that game is removed (for example when a host’s account is deleted) or we no longer need the log to operate the beta.
- **Account metadata** (see above) is kept until you delete your account or we no longer need it to operate the service.
- **Support / abuse emails** you send to **support@manhunt.pivotlattice.app** may be retained as needed to investigate and respond, which can be longer than the 7-day location trail window.
- In-app safety alerts that are part of normal gameplay follow the trail/event rules above; they are **not** given an automatic longer retention unless you also email support about the incident.

## Your rights and controls

- **Display name** — change by signing in again with a new allowed name.
- **Push notifications** — turn off in iOS **Settings → Notifications → Manhunt** (and any in-app control when offered). Removing the device token from our servers also happens when you delete your account.
- **Block / report** — from lobby or live player menus; unblock from **Account → Blocked players**.
- **Leave a hunt** — stops live location broadcast to that game’s other players.
- **Delete account** — **Home → Account → Delete account** (`DELETE /v1/me`). If the in-app control is unavailable, email **support@manhunt.pivotlattice.app**.
- **Access / correction / export** — for beta, email support to request a copy of personal data we hold about your account or to correct account details we can change on the server. We will respond within a reasonable time for a small beta.

## Account deletion

Deleting your account removes your user record, refresh tokens, device token, owned arenas and rule presets, and game memberships from our servers, and signs you out on the device. Games you hosted are removed with their event logs. For games you only joined, past event-log text may still mention the display name you used until those events are removed with the game or age out under retention above. Contact us if you cannot use the in-app flow.

## Service providers and infrastructure

We use third-party infrastructure **only to operate Manhunt**, not to sell your data or show ads. Depending on how this beta is hosted, that may include:

| Category | Examples in this beta | Role |
|---|---|---|
| Edge / tunnel / DNS | **Cloudflare** (for example Cloudflare Tunnel to reach a home-hosted API, DNS, and/or Cloudflare Pages for a static web client) | HTTPS ingress and static hosting |
| Policy hosting | **GitHub Pages** | Publishes this privacy policy |
| Database | **PostgreSQL** on the game host (Docker on the operator’s machine for home-host MVP) | Stores account and game data |
| Operator host | The beta operator’s computer / network running the API | Processes gameplay in real time |
| Push (optional) | **Apple Push Notification service (APNs)** | Delivers optional push alerts when enabled |
| Device OS | Apple iOS / browser vendors | Provide location, Keychain/storage, and system notification settings |

These providers process data on our behalf to deliver the service. They may process limited technical data (for example IP addresses and connection logs) under their own infrastructure policies when you connect to their networks.

We do **not** currently integrate third-party advertising, analytics, or crash-reporting SDKs in the beta apps.

## Security

- API traffic uses **HTTPS**.
- Sensitive location-related payloads are encrypted with **AES-256-GCM** before storage (trail key held by the host).
- Access to the production/beta host and database is limited to operators running the game.
- Session secrets on device use platform storage (Keychain on iOS; browser storage on the web MVP).

No method of transmission or storage is 100% secure. If we become aware of a security incident that affects your personal data, we will take reasonable steps to investigate and will notify affected beta testers via the contact channel we have (for example email to **support@manhunt.pivotlattice.app** replies, in-app notes, or an update to this policy) as appropriate for the severity and what contact information we hold.

## No ads or tracking

Manhunt does not sell personal data, show third-party ads, or use tracking for advertising.

## Contact

Email: **support@manhunt.pivotlattice.app**.

## Policy updates

We may update this policy for beta releases. The **effective date** and **last updated** date appear at the top of this document. Material changes will be reflected in the published version at the URL configured in the app (`ManhuntPrivacyPolicyURL`, currently the GitHub Pages copy). Continued use after an update means you accept the revised policy.
