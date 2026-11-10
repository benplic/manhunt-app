# Manhunt

iOS game for playing real-world Manhunt with friends. The host draws a park, hiders run, seekers hunt, and a home-hosted FastAPI server is the rules engine.

Design: [docs/superpowers/specs/2026-11-08-manhunt-app-design.md](docs/superpowers/specs/2026-11-08-manhunt-app-design.md)

Roadmap: [docs/superpowers/plans/2026-11-09-manhunt-roadmap.md](docs/superpowers/plans/2026-11-09-manhunt-roadmap.md)

## Home host (MVP)

The Mac stays awake for the length of a game. Phones on cellular reach it through a Cloudflare Tunnel. Sideload the app from Xcode.

### 1. Start the server

```bash
cp server/.env.example server/.env   # then replace the signing keys
docker compose up
# optional: docker compose --profile tunnel up
```

Keep the Mac awake:

```bash
caffeinate -dims
```

Health check from this Mac: `curl http://localhost:8000/v1/healthz` should return `{"status":"ok"}`.

### 2. Expose it to phones

**Quick tunnel (default):** `docker compose --profile tunnel up`. Watch the `tunnel` logs for `https://….trycloudflare.com`. That URL changes every time the container starts.

**Named tunnel:** create a tunnel in the Cloudflare Zero Trust dashboard, put the token in `TUNNEL_TOKEN` (never commit it), and change the compose command to `tunnel --no-autoupdate run --token ${TUNNEL_TOKEN}`.

From a phone on **cellular** (not Wi-Fi): `curl https://<host>/v1/healthz` must return 200.

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
cd ios && xcodebuild test -project Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'
```

## License

[MIT](LICENSE)
