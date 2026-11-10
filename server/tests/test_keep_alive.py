from datetime import UTC, datetime
from uuid import uuid4

from app.engine.clock import FakeClock
from app.engine.session import GameSession
from app.presets.classic import classic_preset
from app.realtime.manager import SessionManager
from tests.engine.helpers import square


async def test_keep_replica_awake_pings_while_a_lobby_exists() -> None:
    manager = SessionManager()
    hits: list[int] = []

    async def ping() -> None:
        hits.append(1)

    assert await manager.keep_replica_awake(ping) is False
    session = GameSession(
        game_id=uuid4(),
        arena=square(),
        preset=classic_preset(),
        clock=FakeClock(datetime(2023, 11, 14, tzinfo=UTC)),
        seed=1,
    )
    session.state.phase = "lobby"
    manager.sessions[session.state.game_id] = session
    assert await manager.keep_replica_awake(ping) is True
    assert hits == [1]
    session.state.phase = "ended"
    assert await manager.keep_replica_awake(ping) is False
    assert hits == [1]
