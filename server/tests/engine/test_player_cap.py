"""Lobby size is capped by MAX_GAME_PLAYERS."""

from uuid import uuid4

import pytest

from app.errors import ErrorCode, GameRuleError
from app.limits import MAX_GAME_PLAYERS
from tests.engine.helpers import make_session


def test_add_player_rejects_when_lobby_is_full() -> None:
    session, _ = make_session()
    session.add_player(uuid4(), "Host", is_host=True)
    for index in range(MAX_GAME_PLAYERS - 1):
        session.add_player(uuid4(), f"Guest {index}", is_host=False)
    assert len(session.state.players) == MAX_GAME_PLAYERS
    with pytest.raises(GameRuleError) as exc:
        session.add_player(uuid4(), "One too many", is_host=False)
    assert exc.value.code == ErrorCode.GAME_FULL