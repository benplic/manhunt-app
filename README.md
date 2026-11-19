# Manhunt

iOS game for playing real-world Manhunt with friends. The host draws a park, hiders run, seekers hunt, and a home-hosted FastAPI server is the rules engine.

Design: [docs/superpowers/specs/2026-11-08-manhunt-app-design.md](docs/superpowers/specs/2026-11-08-manhunt-app-design.md)

Roadmap: [docs/superpowers/plans/2026-11-09-manhunt-roadmap.md](docs/superpowers/plans/2026-11-09-manhunt-roadmap.md)

## Home host (MVP)

The Mac stays awake for the length of a game. Phones on cellular reach it through a Cloudflare Tunnel. Sideload the app from Xcode.

### 1. Start the server

```bash
cp server/.env.example .env   # repo root; set MANHUNT_SESSION_SIGNING_KEY, MANHUNT_QR_SIGNING_KEY, MANHUNT_TRAIL_KEY
docker compose up -d
# phones on cellular: start server + db + tunnel and print the verified public URL:
# scripts/home-server.sh up
```

Keep the Mac awake:

```bash
caffeinate -dims
```

Health check from this Mac: `curl http://localhost:8000/v1/healthz` should return `{"status":"ok"}`.

### 2. Expose it to phones

**One command:** `scripts/home-server.sh up` checks free disk, restarts Docker Desktop if its daemon is hung, starts db + server + tunnel, and prints the public URL only after `/v1/healthz` answers 200 through the tunnel. `scripts/home-server.sh status` re-checks everything and exits non-zero if anything is down. Run it before every game.

**Quick tunnel (default):** a random `https://….trycloudflare.com` hostname. It changes every time the `tunnel` container starts, including after a crash or a Docker restart, so a URL from yesterday is dead today. Cloudflare gives quick tunnels no uptime guarantee. A brand-new hostname can take a minute to resolve; a phone that looked it up too early may cache "no such host" for a while (toggle airplane mode to clear it).

**Named tunnel (stable URL, recommended):** in the Cloudflare Zero Trust dashboard create a tunnel with a public hostname on a domain you own, pointing at `http://server:8000`. Put `TUNNEL_TOKEN=…` and `MANHUNT_PUBLIC_URL=https://<that hostname>` in the untracked `.env` (never commit the token). `scripts/home-server.sh up` then uses the `named-tunnel` profile and the URL in the app never changes.

From a phone on **cellular** (not Wi-Fi): `curl https://<host>/v1/healthz` must return 200.

### Keep it up

All services use `restart: unless-stopped`, and the tunnel waits for the server healthcheck. A crashed server comes back on its own with the same tunnel URL.

Docker Desktop hangs when the disk fills, and that silently kills the server and the tunnel. `home-server.sh` refuses to start below 5 GB free and warns below 20 GB. Big, safe-to-regenerate space on a dev Mac: unused simulator runtimes (`xcrun simctl runtime list`, then `xcrun simctl runtime delete <id>`), `xcrun simctl delete unavailable`, `~/Library/Developer/Xcode/DerivedData`, and `docker system prune`.

Also turn on Docker Desktop's "Start Docker Desktop when you sign in" setting, and keep `caffeinate -dims` running during a game.

### 3. Sideload the iOS app

1. Open `ios/Manhunt.xcodeproj` on the Mac.
2. Plug in each friend's iPhone, trust the computer, select the phone as the run destination, and Run.
3. On the phone: Settings → General → VPN & Device Management → trust the developer certificate.
4. On the sign-in screen, set **Server URL** to the `https://….trycloudflare.com` (or named-tunnel) URL. Display name plus **Play** is enough for a home game. Sign in with Apple is for Azure once the paid team is attached.
5. A free Apple ID install expires after 7 days. Reinstall from Xcode. A paid Apple Developer Program membership stretches that to a year.

Debug builds allow local HTTP (`NSAllowsLocalNetworking`) and, for a tunnel-less LAN test, arbitrary HTTP loads.

### 4. Simulator location

Xcode → Debug → Simulate Location → Add GPX File to Project → `ios/Support/GPX/riverside.gpx`.

Playtest checklist: [docs/superpowers/plans/2026-11-09-mvp-playtest.md](docs/superpowers/plans/2026-11-09-mvp-playtest.md)

## External beta (Release)

Use this for TestFlight and other **Release** builds. Home sideload **Debug** still uses the Server URL field and the home-host runbook above.

### Cloud API URL (baked in Release)

Release does not show a Server URL on sign-in. The API origin is compiled in via `MANHUNT_API_BASE_URL` → `ManhuntAPIBaseURL` in `ios/Support/Info.plist` (Release is `https://manhunt.pivotlattice.app`). Testers enter display name, age, and the home key only. Debug keeps `http://localhost:8000` and still shows the Server URL field for local work.

### Home key (party secret)

Cloud/home beta sign-in uses **Play** with display name, age, and the **Home key**: the server’s `MANHUNT_DEV_AUTH_SECRET` from the untracked `.env` on the host (`server/.env.example`). The app stores it in the Keychain so testers are not asked on every launch. Sign in with Apple stays hidden in the repo until the paid Apple team is attached; see the Apple plan below.

### Age 13+

Sign-in requires age. The server and client reject ages under 13 (`TOO_YOUNG`). This is required for external beta, not only for App Store age rating.

### Privacy policy and support

- Policy source: [docs/legal/privacy.md](docs/legal/privacy.md) (HTML mirror at [docs/legal/privacy/index.html](docs/legal/privacy/index.html)).
- GitHub Pages workflow: [`.github/workflows/pages.yml`](.github/workflows/pages.yml) deploys that folder to `https://benplic.github.io/manhunt-app/` (enable **Settings → Pages → GitHub Actions** once; private repos may need a public mirror or GitHub Pro).
- `ManhuntPrivacyPolicyURL` in the Info plists points at that URL. The in-app Privacy policy link and Account screen use this key.
- Support email is `support@manhunt.pivotlattice.app` (`ManhuntSupportEmail` in the Info plists and `docs/legal/privacy.md`).

App Store Connect must list the same privacy and support URLs; that step is in the Apple plan, not in git.

### Account deletion

Testers can delete their account from **Home → Account → Delete account** (`DELETE /v1/me`). That hard-deletes the user and tokens on the server and signs out on the device. See the privacy policy for retention and anonymization on historical game rows.

### Apple Developer Program (human)

Enrollment, bundle id, Sign in with Apple entitlement, App Store Connect metadata, nutrition labels, and the first **external** TestFlight upload are **not** done in the compliance code path. Follow: [docs/superpowers/plans/2026-11-18-apple-developer-account.md](docs/superpowers/plans/2026-11-18-apple-developer-account.md).

Repo-side beta compliance work is tracked in [docs/superpowers/plans/2026-11-18-beta-compliance.md](docs/superpowers/plans/2026-11-18-beta-compliance.md).

## Azure (Phase 2)

Do not turn scale-to-zero on for a shared environment until crash recovery has been tested (`test_restart_rebuilds_mid_game_phase_roles_points_and_locations`). Bicep still ships `minReplicas: 0`.

Human setup (not in git):

1. Azure subscription, resource group `rg-manhunt-prod` (and `rg-manhunt-dev` if you want a sandbox).
2. GitHub OIDC (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) and a GitHub Environment named `prod` that **requires reviewers**.
3. GitHub secrets for `MANHUNT_SESSION_SIGNING_KEY`, `MANHUNT_QR_SIGNING_KEY`, `MANHUNT_TRAIL_KEY` (64 hex chars), `MANHUNT_POSTGRES_ADMIN_PASSWORD`. APNs `.p8` plus `MANHUNT_APNS_KEY`, `MANHUNT_APNS_KEY_ID`, `MANHUNT_APNS_TEAM_ID` once the paid Apple team exists. Never commit those values.
4. Grant the deploying identity Key Vault Administrator on the vault so Bicep can write secrets. The Container App system identity gets Key Vault Secrets User.
5. `workflow_dispatch` `.github/workflows/deploy.yml`. The job waits until `GET /v1/readyz` reports `active_games: 0` before applying Bicep.
6. After the first deploy, confirm a quiet lobby still keeps a replica up (self-ping every 15 s). TODO: verify that on real ACA.

The iOS client shows **Waking the hunt server…** and retries the first request for up to 60 seconds.

## Layout

- `ios/` — SwiftUI client. Domain helpers, AppStore, FakeGameService, LiveGameService.
- `server/` — FastAPI game server (authoritative `GameSession`).
- `infra/` — Azure Bicep (Phase 2).
- `docker-compose.yml` — Postgres 16 + API + optional Cloudflare Tunnel.

## Tests

```bash
cd server && python3 -m venv .venv && . .venv/bin/activate && pip install -e '.[dev]' && pytest -q && ruff check .
# or, with Docker only: docker compose --profile test run --rm server-test
cd ios && xcodebuild test -project Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'
```

On GitHub Actions macOS runners, CI picks an available iPhone 16 Pro simulator automatically (see `.github/workflows/ci.yml`).

## Horizon

Long-term goals only — not in the MVP build. Priority order (do not skip ahead to public):

1. **[Capture the flag](docs/superpowers/plans/2026-11-18-horizon-capture-the-flag.md)** — objective / flag-based park mode
2. **[Senior assassin](docs/superpowers/plans/2026-11-18-horizon-senior-assassin.md)** — longer-cycle elimination among a cohort
3. **[Long-distance persistent](docs/superpowers/plans/2026-11-18-horizon-persistent-long-distance.md)** — friends-at-a-distance intermittent pings; denser clues near frequent places (e.g. a favorite coffee shop)
4. **[Ranked / public lobbies](docs/superpowers/plans/2026-11-18-horizon-ranked-public-lobbies.md)** — stranger matchmaking and ladders (**last** of the four)

## License

[MIT](LICENSE)
