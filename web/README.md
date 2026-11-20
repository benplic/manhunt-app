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

## Hosting choice

**Use Cloudflare Pages on your Cloudflare domain.** Do not put the game on GitHub Pages — that site already serves the privacy policy (`docs/legal/privacy` → `benplic.github.io/manhunt-app`). A Northwest-registered domain is fine as DNS only: point it at Cloudflare (nameservers or CNAME) and attach it as a Pages custom domain.

Why Cloudflare Pages for this app:
- Matches the existing Cloudflare tunnel / API stack
- Easy SPA fallback (`public/_redirects`)
- Custom hostname on a domain you already control
- Separate from the privacy Pages site

## Notes

- Live map uses Leaflet + OSM tiles. Location is watched only while the tab is visible. Safari may suspend GPS when the screen locks — keep the screen on during a hunt.
- Desk / Mac testing: if the browser never delivers GPS, the client waits about 8 seconds, then heartbeats the play-circle center. A real fix, even a coarse one, replaces that seed once (`flag: "reset"`). The **API host must include the going-dark win fix** (`signal_lost` is not a tag). Production on `main` without that fix still ends the hunt as “All hiders were tagged.” Deploy the server branch before mixed iOS + web playtests.
- Verified live phases from the server: `lobby` → `head_start` / `active` (classic), plus `paused` / `ended`.
- Create always posts a fresh 400 m `boundary_circle` arena, then a classic game. No arena editor in v0.
- QR: hiders show `qr_token` via `qrcode`; seekers scan with `html5-qrcode` (no `BarcodeDetector` on iOS Safari). The scanned token is the tag. Join QRs use `/join/{code}` on this site, and the scanner also accepts an older `app.manhunt.ios` path or `?join=` link.
- Access token, refresh token, and home key live in `localStorage` (MVP). Treat the site origin as trusted; XSS can read the party secret.

## Deploy (Cloudflare Pages)

1. Cloudflare Dashboard → Workers & Pages → Create → Pages → Connect to Git → `benplic/manhunt-app`
2. Build settings: root directory `web`, build command `npm run build`, output `dist`
3. Environment variable: `VITE_API_BASE_URL=https://manhunt.pivotlattice.app`
4. After the first deploy, Custom domains → add `play.<your-cloudflare-domain>` (or apex if you prefer)
5. On the API host `.env`, set:
   `MANHUNT_CORS_ORIGINS=http://localhost:5173,http://127.0.0.1:5173,https://play.<your-domain>`
   then restart the API
6. Confirm `GET https://manhunt.pivotlattice.app/v1/healthz` and open the Pages URL on a phone

If the Northwest domain’s DNS is still at Northwest: either change nameservers to Cloudflare, or add a CNAME `play` → `<project>.pages.dev` at Northwest and complete SSL in the Pages custom-domain flow.
