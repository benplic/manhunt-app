# shellcheck shell=bash
# Shared helpers for home-stack .env edits. Source from scripts/; do not execute.

home_env_repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd)"
  printf '%s\n' "$here"
}

# Prints the value for KEY from repo-root .env (no sourcing — values stay out of xtrace).
home_env_file_value() {
  local key="$1" env_file="$2"
  [ -f "$env_file" ] || return 0
  sed -n "s/^${key}=//p" "$env_file" | tail -1 | sed -e 's/^"//' -e 's/"$//'
}

# Sets KEY=VALUE in .env, appending if missing. VALUE must not contain newlines.
home_env_set_kv() {
  local key="$1" value="$2" env_file="$3"
  if [ ! -f "$env_file" ]; then
    printf '%s=%s\n' "$key" "$value" >>"$env_file"
    return 0
  fi
  if grep -q "^${key}=" "$env_file"; then
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$env_file"
    fi
  else
    printf '\n%s=%s\n' "$key" "$value" >>"$env_file"
  fi
}

home_env_random_b64() {
  openssl rand -base64 24 | tr -d '\n'
}

home_env_random_hex() {
  openssl rand -hex 32
}

home_env_prepare_docker() {
  local sock="${HOME}/.docker/run/docker.sock"
  if [ -S "$sock" ]; then
    export DOCKER_HOST="unix://${sock}"
  fi
  if [ "${MANHUNT_DOCKER_NOCREDS:-1}" = 1 ]; then
    local nocreds="${TMPDIR:-/tmp}/manhunt-docker-nocreds"
    mkdir -p "$nocreds"
    printf '%s\n' '{"auths":{}}' >"$nocreds/config.json"
    export DOCKER_CONFIG="$nocreds"
  fi
}