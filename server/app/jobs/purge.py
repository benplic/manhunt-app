"""Daily purge of encrypted location trails older than the host-set retention."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.crypto import TrailKeyError, load_trail_key, open_inputs, seal_inputs
from app.db.models import GameEventRow, GameRow


def _event_time(raw: object) -> datetime | None:
    if not isinstance(raw, str) or not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed


async def purge_trails(session: AsyncSession, days: int = 7) -> int:
    cutoff = datetime.now(UTC) - timedelta(days=days)
    result = await session.execute(
        delete(GameEventRow).where(
            GameEventRow.sensitive.is_(True),
            GameEventRow.created_at < cutoff,
        )
    )
    settings = get_settings()
    try:
        key = load_trail_key(settings.manhunt_trail_key)
    except TrailKeyError:
        key = None
    if key is not None:
        rows = (await session.execute(select(GameRow))).scalars()
        for row in rows:
            try:
                inputs = open_inputs(key, row.inputs)
            except TrailKeyError:
                # TODO: skip rows sealed with a rotated trail key.
                continue
            kept = []
            changed = isinstance(row.inputs, list)
            for item in inputs:
                if not isinstance(item, dict):
                    kept.append(item)
                    continue
                when = _event_time(item.get("at"))
                if item.get("kind") == "location" and when is not None and when < cutoff:
                    changed = True
                    continue
                kept.append(item)
            if changed:
                row.inputs = seal_inputs(key, kept, settings.manhunt_trail_key_id)
    await session.commit()
    return result.rowcount or 0
