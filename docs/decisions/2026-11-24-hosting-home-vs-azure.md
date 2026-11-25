# Hosting decision note: home machine vs Azure Container Apps

Part of `docs/superpowers/plans/2026-11-24-connection-health.md`, Task 6. **No migration is
proposed here.** The decision is the user's. Nothing in this note was deployed.

## Where things are today

- The server runs on a home machine with Docker Compose (`docker-compose.yml`): Postgres 16,
  the FastAPI server, and a Cloudflare Tunnel. A quick tunnel gets a new random hostname on
  every container start; a named tunnel keeps a stable hostname.
- `infra/main.bicep` already describes the Azure shape: Container Apps (consumption, 0.5 vCPU
  and 1 GiB), Postgres Flexible Server `Standard_B1ms`, and Log Analytics. The prod parameters
  set `minReplicas = 0`. `docs/agent/project-context.md` says the Azure deploy is not finished
  and that scale-to-zero is not safe for a live hunt until a human has run the 2.0 checks.

## The question

Does moving to Azure fix the disconnects, and is it worth the cost and work?

## What we know about the disconnects

The 2026-11-23 log (981 `ws_disconnect`, 782 of them `client_close`) has no exception text and
no platform, so the cause is not proven. The connection-health work adds both. Until a repeat
playtest shows the data, the honest answer is that **hosting is one suspect among several**:

- Server side: one slow client stalled the whole broadcast, and the first failed send dropped a
  player. Both are fixed in this plan, independent of where the server runs.
- Client side: iOS and web reconnect logic (no network-change trigger, no resume on foreground).
  Also fixed in this plan.
- Path side: the Cloudflare edge. Cloudflare documents that a WebSocket is closed when no data
  flows for a while, so a heartbeat is required (we send one every 15 s), and that releases of
  their network can restart servers and terminate WebSockets
  ([Cloudflare WebSockets docs](https://developers.cloudflare.com/network/websockets/)). A
  home uplink adds its own variance (Wi-Fi, ISP, power).

Azure Container Apps would remove the home uplink and the quick-tunnel URL churn. It would not
remove the client or server-logic causes, and it would still sit behind its own ingress.

## Options

| | Stay on the home machine | Azure Container Apps, `minReplicas = 1` |
| --- | --- | --- |
| Marginal cost | About zero, plus home power and internet | See estimate below |
| Reliability | Depends on home internet, power, and one machine. A named tunnel fixes the URL churn | Managed platform, no single home machine. Still one replica (`maxReplicas = 1` in Bicep because game state is in memory) |
| Latency | One hop through Cloudflare to the home uplink | Region-local to Azure plus the ingress; pick a region near the players |
| Operations | You own patching, backups, restarts, and the tunnel | Pipeline, image registry, secrets in Key Vault, approvals before prod |
| Security and SOC2 | Secrets in a local `.env`; no approval gate | Fits the Key Vault and approval-gated deploy rules, but the deploy workflow still needs reviewers |
| Crash behavior | Docker `restart: unless-stopped`; crash recovery replays logged inputs | Same recovery code. A restart still drops every socket, so clients must reconnect (this plan improves that) |
| Effort to switch | None | Finish the 2.0 deploy checks, set `minReplicas` to 1, point clients at the new origin, migrate or reset data |

### Cost estimate for Azure (rough, verify before deciding)

I could not read the per-second rates from Microsoft's pricing page (the values are rendered
client-side), so the rates below come from memory and **must be checked in the Azure pricing
calculator**. What the page does confirm
([Container Apps pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/)):

- The first 180,000 vCPU-seconds, 360,000 GiB-seconds, and 2 million requests per subscription
  per month are free.
- A replica kept alive by a minimum replica count is billed at a reduced **idle** rate when it
  is inactive, and at the **active** rate when it is starting, processing requests, or above
  the active thresholds (vCPU above 0.01 cores or more than 1,000 bytes per second received).
  A hunt with many sockets and 1 Hz views is active while it runs.

With 0.5 vCPU and 1 GiB for a 30 day month (about 2.6 million seconds) at the idle rate I
remember (about $0.000003 per vCPU-second and per GiB-second), the always-on replica is on the
order of **$10 per month** after the free grant. Active hours during hunts add to that.
Postgres Flexible `Standard_B1ms` and Log Analytics are separate and run all month. A planning
figure of **roughly $25 to $40 per month all in** is reasonable, but treat it as unverified
until the calculator says otherwise.

## Recommendation

1. **Do not migrate yet.** Run a repeat playtest on the home server with the new logging.
2. Use the data: `python server/scripts/ws_disconnects_by_platform.py <daily log>` groups
   disconnects per minute by `platform` and shows the close codes and reasons.
3. Move to a **named** Cloudflare tunnel now if you are still on a quick tunnel (free, removes
   the URL churn).
4. If disconnects are still high after the server and client fixes, and the log points at the
   edge or the home uplink (many `client_close` with abnormal codes across both platforms at the
   same moments), then pilot Azure with `minReplicas = 1` for one playtest night and compare
   disconnects per minute side by side.
5. If the log shows iOS far worse than web on the same server, the cause is the iOS client or
   iOS networking (background, cellular), and Azure would not help.

## Open questions for the user

- How many playtest hours per month do you expect? That sets whether always-on is worth about
  $10 per month versus scale to zero with a manual wake before a hunt.
- Is a single replica acceptable long term, given game state is held in memory?
- Do you want the Azure pilot to wait for the 2.0 human deploy checks, or run in a dev
  subscription first?
