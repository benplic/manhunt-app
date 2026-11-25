"""Answer "is iOS more stable than web?" from a playtest log.

Usage:
    python scripts/ws_disconnects_by_platform.py playtest-logs/daily/2026-11-24.jsonl

Groups `ws_disconnect` lines by `platform` (added by the connection-health work; older
logs have none and land in `unknown`) and prints disconnects per minute of observed log
time, disconnects per player-minute (so 20 iOS players are not compared with 4 web ones
by raw counts), plus the reason and close-code mix. Reads only; never writes.
"""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path


def _parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def analyze(path: Path) -> dict[str, dict]:
    disconnects: dict[str, list[datetime]] = defaultdict(list)
    players: dict[str, set[str]] = defaultdict(set)
    reasons: dict[str, Counter] = defaultdict(Counter)
    codes: dict[str, Counter] = defaultdict(Counter)
    first: datetime | None = None
    last: datetime | None = None
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
                stamp = _parse_ts(record["ts"])
            except (json.JSONDecodeError, KeyError, ValueError):
                # TODO: decide whether a corrupt line should abort instead of being skipped.
                print(f"skipping unreadable line {number}", file=sys.stderr)
                continue
            first = stamp if first is None or stamp < first else first
            last = stamp if last is None or stamp > last else last
            platform = str(record.get("platform", "unknown"))
            if record.get("event") in {"ws_connect", "ws_reconnect"} and record.get("player_id"):
                players[platform].add(str(record["player_id"]))
            if record.get("event") != "ws_disconnect":
                continue
            disconnects[platform].append(stamp)
            reasons[platform][str(record.get("reason", "unknown"))] += 1
            codes[platform][str(record.get("close_code", "none"))] += 1
    minutes = max(((last - first).total_seconds() / 60.0) if first and last else 0.0, 1 / 60)
    # A platform with players but no disconnects is the best result, so it must be listed.
    return {
        platform: {
            "disconnects": len(disconnects.get(platform, [])),
            "per_minute": round(len(disconnects.get(platform, [])) / minutes, 2),
            "players": len(players[platform]),
            # TODO: assumes every counted player stayed for the whole log window.
            "per_player_minute": (
                round(len(disconnects.get(platform, [])) / minutes / len(players[platform]), 3)
                if players[platform]
                else None
            ),
            "reasons": dict(reasons[platform]),
            "close_codes": dict(codes[platform]),
        }
        for platform in sorted(set(disconnects) | set(players))
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    path = Path(argv[1])
    if not path.is_file():
        print(f"not a file: {path}", file=sys.stderr)
        return 1
    print(json.dumps(analyze(path), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
