# Web later features (revisit)

Deferred from the 2026-11-19 mobile-first web overhaul. Shipped in that pass: privacy policy links (Sign-in + Account), device-local block/unblock + report mailto (lobby + live scores), going-dark win fix, scan accuracy gate, rematch/host pause-undo, refresh rejoin, and mobile live HUD. Pairing stays 30 m. Background GPS stays native-only.

## Deferred product

| Feature | Essential | Feasible | Notes |
|---------|-----------|----------|-------|
| Power-ups with no map target (Ghost, Radar, Jammer, Shield, Scan, Lockdown, Shrink now, Tracker) | 3 | 4 | `POST /power-ups` exists; chip dock is the work |
| Power-ups that drop a point or pick a player (Decoy, Create safe, Move safe, Rescue) | 2 | 3 | Needs map-pick UX on a phone |
| Taunt | 2 | 5 | Route exists |
| Move lobby circle center | 3 | 4 | Radius already editable |
| Kick / remove lobby player | 3 | 4 | Route exists |
| Report player (mailto) | 3 | 4 | Same payload as iOS `PlayerReportMail` |
| Full event log sheet | 3 | 4 | Wire `onEvent` already parsed in `GameSocket` |
| Account delete | 3 | 5 | Auth delete route exists |
| Join-QR camera polish | 4 | 3 | Works; in-app browsers still break permission |
| Pin glide animation | 2 | 4 | |
| Ping flash overlay | 2 | 4 | |
| Arena polygon editor | 2 | 2 | Keep on iOS |
| Full preset / module editor | 2 | 2 | Keep on iOS |
| Flashlight | 1 | 2 | Phone already has one |
| Voice | 1 | 1 | Still a placeholder on iOS |
| Push / installed PWA | 2 | 2 | Separate permission project |
| Haptics as a feature | 2 | 2 | Safari vibration is unreliable |
| Demo bot panel | 1 | 4 | |
| Apple / production identity on web | 2 | 3 | Dev home-key auth stays for friends |

## Cross-compatibility: web ↔ iOS

**Verdict: feasible at about 4/5 for play, not 5/5 for parity.**

Both clients already talk to the same FastAPI host, the same `PlayerView` wire shape, the same WebSocket (`hello` / `view` / `qr_token` / `location` / `event`), and the same QR tag claim. A phone on the site and a phone on the app can share one lobby and one hunt today. That is the cross-compat that matters.

### What already works across clients

- Join codes and invite URLs
- Lobby roles, start, leave, host end
- Live location uplink and filtered map pins
- Rotating hider QR + seeker claim
- Classic module defaults (head start, fuzzy reveal, OOB, going dark, win)

### What the app does not need to change for mixed parties

- Engine distance math (111,320 m/degree)
- Tag pairing distance (fixed 30 m)
- Reveal / zone / points payloads
- Error code enum strings

### What should change on the app (and shared server) for a clean mixed hunt

These are shared-engine or shared-copy fixes, not “rebuild the iOS client”:

1. **Win + going dark** — A `signal_lost` hider must not count as tagged. Without this, a Safari tab that stops GPS can end the match for everyone, including iOS players.
2. **Presence on rejected GPS jumps** — A too-fast fix should refresh `last_location_at` without moving the pin, so browser noise does not push someone dark while iOS stays precise.
3. **Tag error messages** — Keep `NOT_IN_PAIRING_RANGE`, but distinguish no fix / coarse GPS / too far. iOS `AppStore.copy(for:)` should use the server message (or the same three strings) so a web hider with fuzzy GPS does not look like “too far” on an iOS seeker.
4. **Optional: longer web OOB** — Web already posts `oob_countdown: 60`. iOS hosts using classic 15 s will feel harsher for browser friends. Document that, or let the host see the value in the lobby summary.

### What cannot be made equal without leaving the browser

| Gap | Why |
|-----|-----|
| Background location | Safari suspends watchers; iOS uses a When-In-Use background session |
| Always-precise GPS | Browser accuracy often exceeds the 30 m cutoff; CoreLocation usually does not |
| Camera reliability | In-app browsers and permission UX vary; VisionKit is steadier |
| Flashlight / haptics / push | Weak or missing Web APIs vs native |
| Arena + preset editors | Feasible on web, poor on a phone; keep native |

### Practical rule for mixed playtests

- Prefer **iOS for seekers who tag**, or accept that web seekers need a clear accuracy chip and manual code entry.
- Prefer **keep the tab visible and screen on** for every web player, or they go dark.
- Treat the site as the **friends-who-cannot-sideload** client, not a second full editor.

## When to reopen this file

Reopen when a playtest with mixed web + iOS parties is green on tag + going-dark, and someone asks for power-ups or host kick on the site.
