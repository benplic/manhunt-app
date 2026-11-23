#!/usr/bin/env bash
# Rotate the party home key (MANHUNT_DEV_AUTH_SECRET) and restart the API.
#
#   scripts/rotate-home-key.sh
#   scripts/rotate-home-key.sh --revoke-sessions   # also run revoke-party-sessions.sh
#   scripts/rotate-home-key.sh --dry-run
#   scripts/rotate-home-key.sh --print-key         # print new key once (interactive only)
#
# Schedule on the home Mac (cron, launchd, Shortcuts) to stop new sign-ins with the
# old key. Without --revoke-sessions, people who already signed in keep API access
# until their refresh token expires (~30 days).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/home-env.sh
source "$REPO_ROOT/scripts/lib/home-env.sh"

cd "$REPO_ROOT"
ENV_FILE="$REPO_ROOT/.env"
DRY_RUN=0
REVOKE=0
PRINT_KEY=0

log() { printf '[rotate-home-key] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

usage() {
  printf 'usage: %s [--dry-run] [--revoke-sessions] [--print-key]\n' "$0" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --revoke-sessions) REVOKE=1; shift ;;
    --print-key) PRINT_KEY=1; shift ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE (copy from server/.env.example)"

NEW_SECRET="$(home_env_random_b64)"
if [ "${#NEW_SECRET}" -lt 16 ]; then
  fail "generated secret too short"
fi

if [ "$DRY_RUN" = 1 ]; then
  log "dry-run: would set MANHUNT_DEV_AUTH_SECRET and recreate server"
  if [ "$REVOKE" = 1 ]; then
    log "dry-run: would also revoke all sessions"
  fi
  exit 0
fi

home_env_prepare_docker
if ! docker compose ps --status running db server 2>/dev/null | grep -q server; then
  fail "server container is not running; start with scripts/home-server.sh up"
fi

home_env_set_kv MANHUNT_DEV_AUTH_SECRET "$NEW_SECRET" "$ENV_FILE"
log "updated MANHUNT_DEV_AUTH_SECRET in .env"

log "recreating server container"
docker compose up -d --force-recreate --no-deps server

for _ in $(seq 1 30); do
  if curl -sf --max-time 3 "http://127.0.0.1:8000/v1/healthz" | grep -q '"ok"'; then
    break
  fi
  sleep 2
done
curl -sf --max-time 3 "http://127.0.0.1:8000/v1/healthz" | grep -q '"ok"' \
  || fail "server did not answer /v1/healthz after recreate"

if [ "$REVOKE" = 1 ]; then
  log "revoking existing sessions"
  "$REPO_ROOT/scripts/revoke-party-sessions.sh"
fi

if [ "$PRINT_KEY" = 1 ]; then
  printf '%s\n' "$NEW_SECRET"
else
  log "new home key is in .env (not printed). Use --print-key when rotating interactively."
fi

log "done"