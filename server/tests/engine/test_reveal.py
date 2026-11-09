from uuid import uuid4

from tests.engine.helpers import make_session, meters, reading, run_for


def test_fuzzy_reveal_emits_pins_on_interval() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {"interval": 2, "display": 5, "fuzz": 0},
            "signal_loss": {"silence": 60},
        }
    )
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    session.record_location(hid, reading(meters(40, 40), clock))
    run_for(session, clock, 1)
    assert session.state.reveals == []
    run_for(session, clock, 1)
    assert len(session.state.reveals) == 1
    assert session.state.reveals[0].player_id == hid
