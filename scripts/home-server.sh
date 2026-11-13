#!/usr/bin/env bash
# Start and check the home Manhunt stack (db + server + Cloudflare tunnel).
#
#   scripts/home-server.sh up       start or repair the stack, print the verified public URL
#   scripts/home-server.sh status   report disk, Docker, local health, public URL; non-zero if broken
#   scripts/home-server.sh url      print the current public URL only
#
# A URL is only printed as working after /v1/healthz answers 200 through the
# tunnel. A quick-tunnel URL changes whenever the tunnel container restarts, so
# re-run `status` before a game and paste whatever it prints into the app.
#
# Named tunnel: put TUNNEL_TOKEN and MANHUNT_PUBLIC_URL (e.g. https://manhunt.example.com)
# in the untracked .env. The script then uses the named-tunnel profile.
#
# Environment knobs:
#   MANHUNT_MIN_FREE_GB    refuse to start below this much free disk (default 5)
#   MANHUNT_WARN_FREE_GB   warn below this much free disk (default 20)
#   MANHUNT_DOCKER_NOCREDS 1 (default) runs docker with an empty credential config,
#                          because the Docker Desktop credential helper on this Mac
#                          can hang the CLI. Set 0 if you need registry logins.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MIN_FREE_GB="${MANHUNT_MIN_FREE_GB:-5}"
WARN_FREE_GB="${MANHUNT_WARN_FREE_GB:-20}"
DOCKER_SOCK="${HOME}/.docker/run/docker.sock"
LOCAL_HEALTH_URL="http://127.0.0.1:8000/v1/healthz"

log() { printf '[home-server] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

# Reads KEY=value from .env without sourcing it, so the token never enters this shell's output.
env_file_value() {
  local key="$1"
  [ -f .env ] || return 0
  sed -n "s/^${key}=//p" .env | tail -1 | sed -e 's/^"//' -e 's/"$//'
}

PUBLIC_URL_OVERRIDE="${MANHUNT_PUBLIC_URL:-$(env_file_value MANHUNT_PUBLIC_URL)}"
HAS_TUNNEL_TOKEN=0
if [ -n "${TUNNEL_TOKEN:-}" ] || [ -n "$(env_file_value TUNNEL_TOKEN)" ]; then
  HAS_TUNNEL_TOKEN=1
fi

if [ "$HAS_TUNNEL_TOKEN" = 1 ] && [ -n "$PUBLIC_URL_OVERRIDE" ]; then
  TUNNEL_PROFILE="named-tunnel"
  TUNNEL_SERVICE="tunnel-named"
else
  TUNNEL_PROFILE="tunnel"
  TUNNEL_SERVICE="tunnel"
  if [ "$HAS_TUNNEL_TOKEN" = 1 ]; then
    log "TUNNEL_TOKEN is set but MANHUNT_PUBLIC_URL is not; using the quick tunnel."
  fi
fi

if [ "${MANHUNT_DOCKER_NOCREDS:-1}" = 1 ]; then
  NOCREDS_DIR="${TMPDIR:-/tmp}/manhunt-docker-nocreds"
  mkdir -p "$NOCREDS_DIR"
  if [ -d "${HOME}/.docker/cli-plugins" ] && [ ! -e "$NOCREDS_DIR/cli-plugins" ]; then
    ln -s "${HOME}/.docker/cli-plugins" "$NOCREDS_DIR/cli-plugins"
  fi
  printf '%s\n' '{"auths":{}}' > "$NOCREDS_DIR/config.json"
  export DOCKER_CONFIG="$NOCREDS_DIR"
fi
if [ -S "$DOCKER_SOCK" ]; then
  export DOCKER_HOST="unix://${DOCKER_SOCK}"
fi

# macOS has no `timeout`; run a command and kill it if it outlives the limit.
run_with_timeout() {
  local seconds="$1"; shift
  "$@" &
  local pid=$!
  # Detached from stdout so a pipeline reading "$@" is not held open by the sleep.
  ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watchdog=$!
  local status=0
  wait "$pid" || status=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$status"
}

compose() {
  docker compose --profile "$TUNNEL_PROFILE" "$@"
}

free_gb() {
  # Data volume on macOS, root elsewhere.
  local mount="/System/Volumes/Data"
  [ -d "$mount" ] || mount="/"
  df -k "$mount" | awk 'NR==2 { printf "%d", $4 / 1048576 }'
}

check_disk() {
  local free
  free="$(free_gb)"
  if [ "$free" -lt "$MIN_FREE_GB" ]; then
    log "ERROR: only ${free} GB free. Docker Desktop hangs when the disk fills, which kills the server and tunnel. Free space first (see README, Keep it up)."
    return 1
  elif [ "$free" -lt "$WARN_FREE_GB" ]; then
    log "WARNING: only ${free} GB free. A full disk will take the server down mid-game."
  else
    log "disk: ${free} GB free"
  fi
}

docker_alive() {
  [ -S "$DOCKER_SOCK" ] && curl -s --max-time 3 --unix-socket "$DOCKER_SOCK" http://localhost/_ping | grep -q OK
}

ensure_docker() {
  if docker_alive; then
    log "docker: daemon answering"
    return 0
  fi
  log "docker: daemon not answering; restarting Docker Desktop"
  osascript -e 'quit app "Docker Desktop"' >/dev/null 2>&1 || true
  sleep 3
  # A hung backend ignores the quit request.
  pkill -9 -f com.docker.backend 2>/dev/null || true
  open -a Docker || fail "could not launch Docker Desktop"
  local i
  for i in $(seq 1 30); do
    if docker_alive; then
      log "docker: daemon answering after restart"
      return 0
    fi
    sleep 4
  done
  fail "Docker Desktop did not come back within 2 minutes"
}

local_healthy() {
  curl -s --max-time 5 "$LOCAL_HEALTH_URL" | grep -q '"ok"'
}

wait_local_health() {
  local i
  for i in $(seq 1 30); do
    if local_healthy; then
      log "server: healthy on localhost"
      return 0
    fi
    sleep 2
  done
  fail "server did not answer $LOCAL_HEALTH_URL within 60 s. Check: docker compose logs server"
}

current_public_url() {
  if [ "$TUNNEL_PROFILE" = "named-tunnel" ]; then
    printf '%s\n' "${PUBLIC_URL_OVERRIDE%/}"
    return 0
  fi
  # Logs cover only the current container, so the last URL printed is the live one.
  run_with_timeout 20 docker compose --profile tunnel logs --no-log-prefix tunnel 2>/dev/null \
    | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1
}

# Resolves through 1.1.1.1 rather than the system resolver. Probing a new quick-tunnel
# hostname before Cloudflare publishes it leaves a cached "no such host" in macOS's
# resolver, which then reports a healthy tunnel as dead for minutes.
public_healthy() {
  local url="$1" host ip code
  host="${url#https://}"
  host="${host%%/*}"
  ip=""
  if command -v dig >/dev/null 2>&1; then
    ip="$(dig +short +time=3 +tries=1 "$host" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | head -1 || true)"
  fi
  if [ -n "$ip" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve "${host}:443:${ip}" "${url}/v1/healthz" || true)"
  else
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}/v1/healthz" || true)"
  fi
  [ "$code" = 200 ]
}

tunnel_registered() {
  run_with_timeout 20 docker compose --profile "$TUNNEL_PROFILE" logs --no-log-prefix "$TUNNEL_SERVICE" 2>/dev/null \
    | grep -q 'Registered tunnel connection'
}

wait_public_url() {
  local url="" i
  for i in $(seq 1 30); do
    if ! tunnel_registered; then
      sleep 3
      continue
    fi
    url="$(current_public_url || true)"
    if [ -n "$url" ] && public_healthy "$url"; then
      printf '%s\n' "$url"
      return 0
    fi
    sleep 3
  done
  fail "tunnel never answered /v1/healthz (last URL: ${url:-none}). Check: docker compose logs ${TUNNEL_SERVICE}"
}

cmd_up() {
  check_disk || exit 1
  ensure_docker
  log "starting db, server, ${TUNNEL_SERVICE}"
  run_with_timeout 600 compose up -d --build db server "$TUNNEL_SERVICE" \
    || fail "docker compose up failed or hung"
  wait_local_health
  local url
  url="$(wait_public_url)"
  log "public: healthy through the tunnel"
  printf '%s\n' "$url"
}

cmd_status() {
  local broken=0 url
  check_disk || broken=1
  if docker_alive; then log "docker: daemon answering"; else log "docker: NOT answering"; broken=1; fi
  if local_healthy; then log "server: healthy on localhost"; else log "server: NOT answering on localhost"; broken=1; fi
  url="$(current_public_url || true)"
  if [ -z "$url" ]; then
    log "tunnel: no public URL found"
    broken=1
  elif public_healthy "$url"; then
    log "tunnel: healthy"
    printf '%s\n' "$url"
  else
    log "tunnel: ${url} does NOT answer /v1/healthz"
    broken=1
  fi
  if [ "$broken" = 1 ]; then
    log "broken; run: scripts/home-server.sh up"
    return 1
  fi
}

case "${1:-}" in
  up) cmd_up ;;
  status) cmd_status ;;
  url) current_public_url ;;
  *) printf 'usage: %s {up|status|url}\n' "$0" >&2; exit 2 ;;
esac
