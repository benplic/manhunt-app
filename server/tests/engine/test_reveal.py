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


def test_precise_persistent_pin_has_no_radius_and_does_not_expire() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {
                "location_mode": "precise",
                "persistence": "persistent",
                "interval": 2,
                "display": 5,
                "fuzz": 40,
            },
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
    run_for(session, clock, 2)
    pin = session.state.reveals[0]
    assert pin.radius_m == 0
    assert pin.lat == session.state.players[hid].location.point.lat
    run_for(session, clock, 30)
    assert len(session.state.reveals) == 1
    assert session.state.reveals[0].player_id == hid


def test_timed_hints_clear_after_the_display_window() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {
                "location_mode": "fuzzy",
                "persistence": "timed",
                "interval": 2,
                "display": 2,
                "fuzz": 0,
                "hints_enabled": True,
                "hints_persistence": "timed",
                "hints_interval": 5,
            },
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
    session.record_location(seek, reading(meters(80, 40), clock))
    run_for(session, clock, 2)
    assert session.state.players[seek].hint is not None
    run_for(session, clock, 2)
    assert session.state.players[seek].hint is None


def test_hot_cold_mode_publishes_hints_without_pins() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "reveal_fuzzy": {
                "location_mode": "hot_cold",
                "persistence": "timed",
                "interval": 2,
                "display": 5,
                "fuzz": 30,
                "hints_enabled": False,
                "hints_persistence": "persistent",
                "hints_interval": 2,
            },
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
    session.record_location(seek, reading(meters(80, 40), clock))
    run_for(session, clock, 2)
    assert session.state.reveals == []
    assert session.state.players[seek].hint is not None
