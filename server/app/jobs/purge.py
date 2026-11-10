"""Daily purge of encrypted location trails older than the host-set retention."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import GameEventRow


async def purge_trails(session: AsyncSession, days: int = 7) -> int:
    cutoff = datetime.now(UTC) - timedelta(days=days)
    result = await session.execute(
        delete(GameEventRow).where(
            GameEventRow.sensitive.is_(True),
            GameEventRow.created_at < cutoff,
        )
    )
    await session.commit()
    return result.rowcount or 0
