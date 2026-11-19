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

- Location only while the tab is visible. Safari may suspend GPS when the screen locks — keep the screen on during a hunt.
- Create always posts a fresh 400 m `boundary_circle` arena, then a classic game. No arena editor in v0.
- Access token, refresh token, and home key live in `localStorage` (MVP). Treat the site origin as trusted; XSS can read the party secret.

## Deploy

Build static assets with `npm run build` and host `dist/` on Cloudflare Pages (or any static HTTPS host). Set `VITE_API_BASE_URL` at build time. The API must allow the Pages origin via CORS (server change in a later task).
