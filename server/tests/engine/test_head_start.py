from uuid import uuid4

import pytest

from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import make_session, run_for


def test_head_start_honors_duration_then_unlocks() -> None:
    session, clock = make_session(overrides={"head_start": {"duration": 12}})
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    assert session.state.phase == "head_start"
    run_for(session, clock, 11)
    assert session.state.phase == "head_start"
    run_for(session, clock, 1)
    assert session.state.phase == "active"


def test_disabled_head_start_starts_active_and_needs_both_roles() -> None:
    session, _clock = make_session(overrides={"head_start": {"enabled": False}})
    a = uuid4()
    b = uuid4()
    session.add_player(a, "Riley", True)
    session.add_player(b, "Jordan", False)
    with pytest.raises(GameRuleError) as exc:
        session.start()
    assert exc.value.code == ErrorCode.NEED_BOTH_ROLES
    session.assign_roles_random(1)
    session.start()
    assert session.state.phase == "active"


def test_pause_freezes_the_head_start_clock() -> None:
    session, clock = make_session(overrides={"head_start": {"duration": 5}})
    session.add_player(uuid4(), "Riley", True)
    session.add_player(uuid4(), "Jordan", False)
    session.assign_roles_random(1)
    session.start()
    session.pause()
    run_for(session, clock, 20)
    assert session.state.phase == "paused"
    session.resume()
    assert session.state.phase == "head_start"
    run_for(session, clock, 5)
    assert session.state.phase == "active"
