"""Live join codes cannot collide. Ended and abandoned games may reuse a code."""

from __future__ import annotations

import asyncio
from pathlib import Path
from uuid import uuid4

import pytest
from alembic.config import Config
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from alembic import command
from app.db.models import GameRow, User

SERVER_ROOT = Path(__file__).resolve().parents[2]


def _upgrade(db_path: Path) -> str:
    url = f"sqlite+aiosqlite:///{db_path}"
    cfg = Config(str(SERVER_ROOT / "alembic.ini"))
    cfg.set_main_option("sqlalchemy.url", url)
    command.upgrade(cfg, "head")
    return url


def _game(host_id, code: str, status: str) -> GameRow:
    return GameRow(
        id=uuid4(),
        join_code=code,
        host_id=host_id,
        status=status,
        arena_snapshot={"name": "park"},
        preset_snapshot={"id": "classic"},
        seed=1,
        inputs=[],
    )


def test_live_join_code_is_unique_and_reusable_after_end(tmp_path: Path) -> None:
    """Two live games with the same code fail. An ended game may reuse it."""
    url = _upgrade(tmp_path / "codes.db")

    async def run() -> None:
        engine = create_async_engine(url)
        factory = async_sessionmaker(engine, expire_on_commit=False)
        async with factory() as session:
            host = User(id=uuid4(), display_name="Casey", dev_handle="casey")
            session.add(host)
            await session.commit()
            # Copy the id before the failed commit expires the instance.
            host_id = host.id

            session.add(_game(host_id, "PARK42", "lobby"))
            await session.commit()
            session.add(_game(host_id, "PARK42", "active"))
            with pytest.raises(IntegrityError):
                await session.commit()

        async with factory() as session:
            session.add(_game(host_id, "PARK42", "ended"))
            await session.commit()
            session.add(_game(host_id, "PARK42", "abandoned"))
            await session.commit()

            rows = (
                await session.scalars(select(GameRow).where(GameRow.join_code == "PARK42"))
            ).all()
            assert {row.status for row in rows} == {"lobby", "ended", "abandoned"}
        await engine.dispose()

    asyncio.run(run())
