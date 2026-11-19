#!/usr/bin/env bash
# Capture non-sensitive game_events for open hunts into playtest-logs/.
#
#   scripts/playtest-event-log.sh once     # snapshot now
#   scripts/playtest-event-log.sh watch    # refresh every 15s until Ctrl-C / ended
#
# Reads Postgres via docker compose exec. Does not print secrets.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/playtest-logs"
STAMP="$(date +%Y-%m-%d)"
MD="$LOG_DIR/${STAMP}-playtest-events.md"
JSON="$LOG_DIR/${STAMP}-playtest-events.json"

DOCKER_SOCK="${HOME}/.docker/run/docker.sock"
if [ -S "$DOCKER_SOCK" ]; then
  export DOCKER_HOST="unix://${DOCKER_SOCK}"
fi
if [ "${MANHUNT_DOCKER_NOCREDS:-1}" = 1 ]; then
  NOCREDS_DIR="${TMPDIR:-/tmp}/manhunt-docker-nocreds"
  mkdir -p "$NOCREDS_DIR"
  printf '%s\n' '{"auths":{}}' > "$NOCREDS_DIR/config.json"
  export DOCKER_CONFIG="$NOCREDS_DIR"
fi

mkdir -p "$LOG_DIR"

dump_json() {
  docker compose exec -T server python <<'PY'
import json, os
from sqlalchemy import create_engine, text

url = os.environ["MANHUNT_DATABASE_URL"]
eng = create_engine(url)
out = []
with eng.connect() as c:
    games = c.execute(
        text(
            """
            select id::text, join_code, status, created_at
            from games
            where status not in ('ended', 'abandoned')
            order by created_at desc
            """
        )
    ).fetchall()
    for row in games:
        gid, code, status, created = row
        players = c.execute(
            text(
                """
                select u.display_name, gp.role, gp.status
                from game_players gp
                join users u on u.id = gp.user_id
                where gp.game_id = :g
                order by u.display_name
                """
            ),
            {"g": gid},
        ).fetchall()
        events = c.execute(
            text(
                """
                select seq, type, payload, created_at
                from game_events
                where game_id = :g and sensitive = false
                order by seq
                """
            ),
            {"g": gid},
        ).fetchall()
        out.append(
            {
                "game_id": gid,
                "join_code": code,
                "status": status,
                "created_at": str(created),
                "players": [
                    {"name": p[0], "role": p[1], "status": p[2]} for p in players
                ],
                "events": [
                    {
                        "seq": e[0],
                        "type": e[1],
                        "payload": e[2],
                        "at": str(e[3]),
                    }
                    for e in events
                ],
            }
        )
print(json.dumps(out, default=str))
PY
}

write_md() {
  local json_path="$1"
  local md_path="$2"
  python3 - "$json_path" "$md_path" <<'PY'
import json, sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

src, dest = Path(sys.argv[1]), Path(sys.argv[2])
data = json.loads(src.read_text())
now = datetime.now(ZoneInfo("America/New_York")).strftime("%Y-%m-%d %I:%M:%S %p ET")
lines = [
    "# Playtest event log",
    "",
    f"Last refresh: {now}",
    "Source: home-server Postgres `game_events` (sensitive rows omitted).",
    "In-app: Live hunt → event log sheet also shows the same timeline.",
    "",
]
# Prefer live/active hunts first, then lobby.
order = {"active": 0, "head_start": 0, "paused": 1, "lobby": 2}
data.sort(key=lambda g: (order.get(g["status"], 9), g.get("created_at") or ""), reverse=False)

for g in data:
    lines.append(f"## {g['join_code']} — {g['status']}")
    lines.append("")
    lines.append(f"- game_id: `{g['game_id']}`")
    lines.append(f"- created: {g.get('created_at', '?')}")
    if g["players"]:
        roster = ", ".join(f"{p['name']} ({p['role']}/{p['status']})" for p in g["players"])
        lines.append(f"- players: {roster}")
    else:
        lines.append("- players: _(none)_")
    lines.append("")
    if not g["events"]:
        lines.append("_No persisted events yet (lobby, or events not flushed)._")
        lines.append("")
        continue
    for e in g["events"]:
        payload = e.get("payload") or {}
        text = ""
        if isinstance(payload, dict):
            text = payload.get("text") or json.dumps(payload, ensure_ascii=False)
        else:
            text = str(payload)
        lines.append(f"- `{e['seq']:04d}` **{e['type']}** @ {e['at']}: {text}")
    lines.append("")

dest.write_text("\n".join(lines) + "\n")
print(dest)
PY
}

snapshot() {
  dump_json > "$JSON"
  write_md "$JSON" "$MD"
  echo "json: $JSON"
  echo "md:   $MD"
}

case "${1:-once}" in
  once) snapshot ;;
  watch)
    log() { printf '[playtest-log] %s\n' "$*" >&2; }
    log "writing to $MD (Ctrl-C to stop)"
    while true; do
      snapshot
      sleep 15
    done
    ;;
  *)
    printf 'usage: %s {once|watch}\n' "$0" >&2
    exit 2
    ;;
esac
