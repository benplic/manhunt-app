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


def test_restart_restores_game_whose_log_repeats_a_tag(tmp_path) -> None:
    """PS95VZ shape: TARGET_NOT_ACTIVE during replay used to abandon a live hunt."""
    from datetime import timedelta
    from uuid import UUID

    from app.engine.modules.base import TagClaim
    from app.engine.qr import make_qr_token
    from tests.engine.helpers import make_session

    session, clock = make_session(
        overrides={"head_start": {"enabled": False}, "signal_loss": {"enabled": False}}
    )
    # Must match the QR key make_test_app configures, or replay rejects the token.
    session.qr_signing_key = "y" * 32
    seeker, hider_a, hider_b = uuid4(), uuid4(), uuid4()
    session.add_player(seeker, "Jordan", is_host=True)
    session.add_player(hider_a, "Riley", is_host=False)
    session.add_player(hider_b, "Casey", is_host=False)
    session.set_role(seeker, "seeker")
    session.set_role(hider_a, "hider")
    session.set_role(hider_b, "hider")
    session.start()
    clock.advance(1)
    session.tick()
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider_a,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider_a, qr_token=token))
    inputs = [dict(item) for item in session.state.inputs]
    inputs.append(dict(next(item for item in inputs if item["kind"] == "tag")))

    # The QR token binds to the session's game id, so the row must reuse it.
    game_id = session.state.game_id
    host_id = uuid4()
    app = make_test_app(tmp_path)
    with TestClient(app) as _boot:
        assert _boot.get("/v1/healthz").status_code == 200

    async def seed() -> None:
        async with app.state.session_factory() as db:
            db.add(User(id=host_id, display_name="Casey", dev_handle=f"dev:{host_id}"))
            db.add(
                GameRow(
                    id=game_id,
                    join_code="PS9AAA",
                    host_id=host_id,
                    status="active",
                    arena_snapshot=arena_to_dict(square()),
                    preset_snapshot=session.state.preset,
                    seed=session.state.seed,
                    inputs=inputs,
                )
            )
            await db.commit()

    asyncio.run(seed())

    restarted = make_test_app(tmp_path)
    with TestClient(restarted) as client:
        assert client.get("/v1/healthz").status_code == 200
        rebuilt = restarted.state.manager.sessions.get(UUID(str(game_id)))
        assert rebuilt is not None
        assert rebuilt.state.players[hider_a].status == "eliminated"

    async def check() -> None:
        async with restarted.state.session_factory() as db:
            row = await db.get(GameRow, game_id)
            assert row is not None
            assert row.status == "active"

    asyncio.run(check())
