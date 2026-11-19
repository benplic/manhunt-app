# Manhunt web MVP

Browser client for friends who cannot sideload iOS. Talks to the same FastAPI host as Release iOS.

## Setup

```bash
cd web
cp .env.example .env   # optional; defaults to https://manhunt.pivotlattice.app
npm install
npm test
npm run dev
```

Sign in with display name, age (13+), and the host’s `MANHUNT_DEV_AUTH_SECRET` (home key).

## Notes

- Live map uses Leaflet + OSM tiles. Location is watched only while the tab is visible. Safari may suspend GPS when the screen locks — keep the screen on during a hunt.
- Verified live phases from the server: `lobby` → `head_start` / `active` (classic), plus `paused` / `ended`.
- Create always posts a fresh 400 m `boundary_circle` arena, then a classic game. No arena editor in v0.
- QR: hiders show `qr_token` via `qrcode`; seekers scan with `html5-qrcode` (no `BarcodeDetector` on iOS Safari). Tag distance stays server-side (~30 m).
- Access token, refresh token, and home key live in `localStorage` (MVP). Treat the site origin as trusted; XSS can read the party secret.

## Deploy

1. `cd web && npm run build`
2. Cloudflare Pages project, root `web/`, output `dist` (SPA fallback via `public/_redirects`)
3. Build env: `VITE_API_BASE_URL=https://manhunt.pivotlattice.app`
4. On the API host, set `MANHUNT_CORS_ORIGINS` to include the Pages HTTPS origin (defaults already cover local Vite)
5. Confirm `GET /v1/healthz` on the API and open the Pages URL on a phone
