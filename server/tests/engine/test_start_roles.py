from uuid import uuid4

import pytest

from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import make_session


def test_start_puts_unassigned_players_on_the_hider_team() -> None:
    session, _ = make_session(seed=7)
    host, seeker, late = uuid4(), uuid4(), uuid4()
    session.add_player(host, "Host", is_host=True)
    session.add_player(seeker, "Seeker", is_host=False)
    session.add_player(late, "Late", is_host=False)
    session.set_role(host, "hider")
    session.set_role(seeker, "seeker")

    session.start()

    assert session.state.players[late].role == "hider"
    assert session.state.players[host].role == "hider"
    assert session.state.players[seeker].role == "seeker"


def test_start_still_needs_a_seeker_even_with_unassigned_players() -> None:
    session, _ = make_session(seed=7)
    host, guest = uuid4(), uuid4()
    session.add_player(host, "Host", is_host=True)
    session.add_player(guest, "Guest", is_host=False)
    session.set_role(host, "hider")

    with pytest.raises(GameRuleError) as exc:
        session.start()
    assert exc.value.code == ErrorCode.NEED_BOTH_ROLES
    assert session.state.players[guest].role == "unassigned"
