# Manhunt Privacy Policy

*Draft for external beta. Last updated: 2026-11-18.*

## Who we are

Manhunt is a location-based outdoor game operated for beta testing. This policy describes what we collect, how we use it, and your choices. Questions: **support@manhunt.pivotlattice.app**.

## Data we collect

- **Display name** — shown to other players in your games.
- **Age** — collected at sign-in to enforce a minimum age of 13. We check it when you sign in and store it **only on your device** (`manhunt.ageYears`); we do not persist age on your server user record.
- **Precise location** — while a hunt is open, to enforce the play area, safe zones, tags, and safety features. Sent to our server and shared with other players in that game under the game rules.
- **Installation identifier** — a stable id for this app install, used for authentication and device management.
- **Home auth secret** — stored **only on your device** (Keychain) to restore your session; we do not log this value.
- **Optional push notification token** — if you enable notifications, we store a device token to send game-related alerts.

We do not use advertising SDKs or cross-app tracking.

## How location is shared with other players

During an active hunt, players in the same game can see positions and related gameplay state as defined by that hunt’s rules (including safety alerts where enabled). Location updates stop when the hunt ends or you leave. Manhunt requests **When In Use** location only; it does not ask for Always location access.

## Retention

Gameplay and sensitive location trails on our servers are purged on a rolling basis, with a default **7-day** maximum retention for sensitive location history unless a shorter window applies to a specific feature. Account metadata is kept until you delete your account or we no longer need it to operate the service.

## Account deletion

You can delete your account from the in-app Account screen (when available). Deletion removes your user record, refresh tokens, device token, owned arenas and rule presets, and game memberships from our servers, and signs you out on the device. Games you hosted are removed with their event logs. For games you only joined, past event log text may still mention the display name you used until those events age out under the retention window above. Contact us if you cannot use the in-app flow.

## No ads or tracking

Manhunt does not sell personal data, show third-party ads, or use tracking for advertising. We use HTTPS for API traffic.

## Contact

Email: **support@manhunt.pivotlattice.app**.

## Policy updates

We may update this policy for beta releases. Material changes will be reflected in the published version at the URL configured in the app (`ManhuntPrivacyPolicyURL`). Continued use after an update means you accept the revised policy.