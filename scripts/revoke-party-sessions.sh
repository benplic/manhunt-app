#!/usr/bin/env bash
# End every dev-auth session: drop refresh tokens and rotate the JWT signing key.
#
#   scripts/revoke-party-sessions.sh
#   scripts/revoke-party-sessions.sh --dry-run
#
# Already-signed access JWTs stop working after the server restarts with the new
# MANHUNT_SESSION_SIGNING_KEY. Players must sign in again with the current home key.
# Does not change MANHUNT_DEV_AUTH_SECRET (use rotate-home-key.sh for that).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/home-env.sh
source "$REPO_ROOT/scripts/lib/home-env.sh"

cd "$REPO_ROOT"
ENV_FILE="$REPO_ROOT/.env"
DRY_RUN=0

log() { printf '[revoke-party-sessions] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

usage() {
  printf 'usage: %s [--dry-run]\n' "$0" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE (copy from server/.env.example)"

home_env_prepare_docker
if ! docker compose ps --status running db server 2>/dev/null | grep -q server; then
  fail "server container is not running; start with scripts/home-server.sh up"
fi

NEW_SIGNING="$(home_env_random_hex)"

if [ "$DRY_RUN" = 1 ]; then
  log "dry-run: would TRUNCATE refresh_tokens and rotate MANHUNT_SESSION_SIGNING_KEY"
  exit 0
fi

log "truncating refresh_tokens"
docker compose exec -T db psql -U manhunt -d manhunt -v ON_ERROR_STOP=1 -c "TRUNCATE refresh_tokens;"

home_env_set_kv MANHUNT_SESSION_SIGNING_KEY "$NEW_SIGNING" "$ENV_FILE"
log "rotated MANHUNT_SESSION_SIGNING_KEY in .env"

log "recreating server container"
docker compose up -d --force-recreate --no-deps server

for _ in $(seq 1 30); do
  if curl -sf --max-time 3 "http://127.0.0.1:8000/v1/healthz" | grep -q '"ok"'; then
    log "server healthy"
    exit 0
  fi
  sleep 2
done

fail "server did not answer /v1/healthz after recreate"