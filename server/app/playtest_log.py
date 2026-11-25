"""Append-only JSONL playtest timeline. No coordinates or tokens on disk.

One line per event. Files land under MANHUNT_PLAYTEST_LOG_DIR (default
``playtest-logs/`` for local/test/home):

- ``games/<game_id>.jsonl`` — per-hunt timeline
- ``daily/<YYYY-MM-DD>.jsonl`` — all hunts that day (America/New_York date)
- ``errors.jsonl`` — exceptions and API failures

Writes are line-buffered and lock-guarded. Location traffic is never logged.
"""

from __future__ import annotations

import json
import logging
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

log = logging.getLogger("manhunt.playtest_log")

_ET = ZoneInfo("America/New_York")

# Keys that must never reach the playtest files.
_FORBIDDEN = frozenset(
    {
        "lat",
        "lon",
        "longitude",
        "latitude",
        "token",
        "access_token",
        "refresh_token",
        "qr_token",
        "identity_token",
        "device_token",
        "password",
        "secret",
        "authorization",
    }
)


def _iso_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _day_stamp() -> str:
    return datetime.now(_ET).strftime("%Y-%m-%d")


def _scrub(value: Any) -> Any:
    """Drop secrets/coords; keep scalars and small nested dicts/lists."""
    if isinstance(value, dict):
        clean: dict[str, Any] = {}
        for key, item in value.items():
            if str(key).lower() in _FORBIDDEN:
                continue
            clean[str(key)] = _scrub(item)
        return clean
    if isinstance(value, list):
        return [_scrub(item) for item in value[:40]]
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def _dump_line(record: dict[str, Any]) -> str:
    """One JSON line that keeps real characters (O’Donnell, José, emoji) readable.

    The default `ensure_ascii=True` writes `\\u2019` and emoji as surrogate-pair escapes,
    which is valid JSON but looks corrupted in `less`, Excel, and most log viewers.
    """
    line = json.dumps(record, separators=(",", ":"), default=str, ensure_ascii=False)
    try:
        line.encode("utf-8")
    except UnicodeEncodeError:
        # A lone surrogate (client sent "\ud800" in JSON) cannot be written as UTF-8.
        # Escaping that one line keeps the sink alive and the data intact.
        line = json.dumps(record, separators=(",", ":"), default=str, ensure_ascii=True)
    return line


class PlaytestLogger:
    """Process-wide playtest file sink. Cheap enough for a 30-player lobby."""

    def __init__(self, root: Path | None) -> None:
        self.root = root
        self._lock = threading.Lock()
        # game_id -> player_ids that have completed a WS hello at least once.
        self._seen_ws: dict[str, set[str]] = {}
        if root is not None:
            (root / "games").mkdir(parents=True, exist_ok=True)
            (root / "daily").mkdir(parents=True, exist_ok=True)
            log.info("playtest_log_dir=%s", root)

    @property
    def enabled(self) -> bool:
        return self.root is not None

    def emit(
        self,
        event: str,
        *,
        game_id: UUID | str | None = None,
        player_id: UUID | str | None = None,
        join_code: str | None = None,
        **fields: Any,
    ) -> None:
        if not self.enabled or self.root is None:
            return
        record = {
            "ts": _iso_now(),
            "event": event,
            "game_id": str(game_id) if game_id is not None else None,
            "player_id": str(player_id) if player_id is not None else None,
            "join_code": join_code,
        }
        record.update(_scrub(fields))
        # Drop null tops so files stay skimable.
        line = _dump_line({key: value for key, value in record.items() if value is not None})
        paths = [self.root / "daily" / f"{_day_stamp()}.jsonl"]
        if game_id is not None:
            paths.append(self.root / "games" / f"{game_id}.jsonl")
        if event.startswith("error") or event in {"exception", "api_error", "ws_send_failed"}:
            paths.append(self.root / "errors.jsonl")
        try:
            with self._lock:
                for path in paths:
                    with path.open("a", encoding="utf-8") as handle:
                        handle.write(line + "\n")
        except OSError:
            log.exception("playtest_log_write_failed event=%s", event)

    def ws_connected(
        self,
        game_id: UUID,
        player_id: UUID,
        *,
        join_code: str | None = None,
    ) -> None:
        gid = str(game_id)
        pid = str(player_id)
        with self._lock:
            seen = self._seen_ws.setdefault(gid, set())
            reconnect = pid in seen
            seen.add(pid)
        self.emit(
            "ws_reconnect" if reconnect else "ws_connect",
            game_id=game_id,
            player_id=player_id,
            join_code=join_code,
        )

    def ws_disconnected(
        self,
        game_id: UUID,
        player_id: UUID,
        *,
        join_code: str | None = None,
        reason: str | None = None,
    ) -> None:
        self.emit(
            "ws_disconnect",
            game_id=game_id,
            player_id=player_id,
            join_code=join_code,
            reason=reason,
        )

    def record_engine_events(
        self,
        game_id: UUID,
        events: list[Any],
        *,
        join_code: str | None = None,
    ) -> None:
        """Mirror non-sensitive engine events already drained for the wire."""
        if not self.enabled or not events:
            return
        for event in events:
            if getattr(event, "sensitive", False):
                continue
            payload = dict(getattr(event, "payload", {}) or {})
            # Prefer the public text; drop any nested coords if a module slipped.
            self.emit(
                f"game.{getattr(event, 'type', 'unknown')}",
                game_id=game_id,
                player_id=getattr(event, "player_id", None),
                join_code=join_code,
                seq=getattr(event, "seq", None),
                tone=getattr(event, "tone", None),
                text=getattr(event, "text", None) or payload.get("text"),
                payload=_scrub(payload),
            )


_LOGGER = PlaytestLogger(None)


def configure_playtest_log(root: Path | str | None) -> PlaytestLogger:
    """Install the process logger. Pass None or \"\" to disable."""
    global _LOGGER
    if root is None or root == "":
        _LOGGER = PlaytestLogger(None)
        return _LOGGER
    path = Path(root)
    path.mkdir(parents=True, exist_ok=True)
    _LOGGER = PlaytestLogger(path)
    return _LOGGER


def get_playtest_log() -> PlaytestLogger:
    return _LOGGER
