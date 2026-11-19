"""A broken trail must not keep the home server from booting."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.db.models import GameRow, User
from app.engine.arena import arena_to_dict
from app.presets.classic import classic_preset
from tests.conftest import make_test_app
from tests.engine.helpers import square


def test_restart_abandons_game_when_rebuild_fails(tmp_path) -> None:
    """move_safe pointing at a missing zone used to crash lifespan."""
    game_id = uuid4()
    host_id = uuid4()
    app = make_test_app(tmp_path)

    # Lifespan creates the schema. Seed after the first boot so restart has a row.
    with TestClient(app) as _boot:
        assert _boot.get("/v1/healthz").status_code == 200

    async def seed() -> None:
        async with app.state.session_factory() as session:
            session.add(User(id=host_id, display_name="Casey", dev_handle=f"dev:{host_id}"))
            session.add(
                GameRow(
                    id=game_id,
                    join_code="BAD001",
                    host_id=host_id,
                    status="active",
                    arena_snapshot=arena_to_dict(square()),
                    preset_snapshot=classic_preset(),
                    seed=1,
                    inputs=[
                        {
                            "at": datetime(2023, 11, 14, 12, 0, tzinfo=UTC).isoformat(),
                            "kind": "purchase",
                            "game_elapsed_s": 0,
                            "payload": {
                                "player_id": str(uuid4()),
                                "power_id": "move_safe",
                                "zone_id": str(uuid4()),
                            },
                        }
                    ],
                )
            )
            await session.commit()

    asyncio.run(seed())

    restarted = make_test_app(tmp_path)
    with TestClient(restarted) as client:
        assert client.get("/v1/healthz").status_code == 200
        assert game_id not in restarted.state.manager.sessions

    async def check() -> None:
        async with restarted.state.session_factory() as session:
            row = await session.get(GameRow, game_id)
            assert row is not None
            assert row.status == "abandoned"
            live = (
                await session.execute(
                    select(GameRow).where(GameRow.status.in_(["head_start", "active", "paused"]))
                )
            ).scalars().all()
            assert live == []

    asyncio.run(check())
