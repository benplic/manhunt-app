"""Hiders see seekers through reveal_seekers, independent of reveal_fuzzy."""

import json
from uuid import uuid4

from app.engine.views import build_view
from tests.engine.helpers import make_session, meters, reading, run_for


def _pair(overrides: dict, *, seed: int = 1):
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "signal_loss": {"silence": 60},
            **overrides,
        },
        seed=seed,
    )
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    return session, clock, hid, seek


def _place(session, clock, hid, seek) -> None:
    session.record_location(hid, reading(meters(40, 40), clock))
    session.record_location(seek, reading(meters(80, 40), clock))


def test_default_off_publishes_no_seeker_pins_or_hints() -> None:
    session, clock, hid, seek = _pair(
        {
            "reveal_fuzzy": {
                "location_mode": "fuzzy",
                "interval": 2,
                "display": 10,
                "fuzz": 30,
            }
        }
    )
    _place(session, clock, hid, seek)
    run_for(session, clock, 4)
    assert session.state.seeker_reveals == []
    assert session.state.players[hid].hint is None
    view = build_view(session, hid)
    assert view["timers"]["seeker_reveal_interval_s"] is None
    assert view["timers"]["next_seeker_reveal_in_s"] is None


def test_off_does_not_consume_rng_before_the_hider_pin() -> None:
    def hider_pin(seeker_reveal: dict) -> tuple[float, float]:
        session, clock, hid, seek = _pair(
            {
                "reveal_fuzzy": {
                    "location_mode": "fuzzy",
                    "interval": 2,
                    "display": 20,
                    "fuzz": 30,
                },
                "reveal_seekers": seeker_reveal,
            },
            seed=7,
        )
        _place(session, clock, hid, seek)
        run_for(session, clock, 2)
        pin = session.state.reveals[0]
        return (pin.lat, pin.lon)

    off = hider_pin({"location_mode": "off", "interval": 2, "fuzz": 30})
    # A fuzzy seeker pulse on the same tick would draw from the same RNG.
    # A long interval never reaches that draw, so Off must match it.
    delayed = hider_pin(
        {"location_mode": "fuzzy", "interval": 600, "display": 10, "fuzz": 30}
    )
    assert off == delayed


def test_fuzzy_timed_seeker_pin_is_hider_only_and_expires() -> None:
    session, clock, hid, seek = _pair(
        {
            "reveal_fuzzy": {"interval": 600, "display": 10, "fuzz": 0},
            "reveal_seekers": {
                "location_mode": "fuzzy",
                "persistence": "timed",
                "interval": 6,
                "display": 5,
                "fuzz": 0,
                "hints_enabled": False,
            },
        }
    )
    _place(session, clock, hid, seek)
    run_for(session, clock, 6)
    assert len(session.state.seeker_reveals) == 1
    assert session.state.seeker_reveals[0].player_id == seek
    assert session.state.reveals == []
    events = [e for e in session.drain_events() if e.type == "reveal"]
    assert any(e.text == "Seeker pins are up." for e in events)

    hider_view = build_view(session, hid)
    seeker_view = build_view(session, seek)
    hider_pins = {pin["player_id"] for pin in hider_view["reveals"]}
    seeker_pins = {pin["player_id"] for pin in seeker_view["reveals"]}
    assert str(seek) in hider_pins
    assert str(seek) not in seeker_pins
    seeker_row = next(row for row in hider_view["players"] if row["player_id"] == str(seek))
    assert seeker_row["location"] is None
    assert "is_decoy" not in json.dumps(hider_view)
    assert hider_view["timers"]["seeker_reveal_interval_s"] == 6
    assert hider_view["timers"]["next_seeker_reveal_in_s"] == 6

    # Display is 5s. The next pulse is 6s out, so the pin is gone for one tick.
    run_for(session, clock, 5)
    assert session.state.seeker_reveals == []


def test_precise_persistent_pin_matches_the_seeker_and_does_not_expire() -> None:
    session, clock, hid, seek = _pair(
        {
            "reveal_seekers": {
                "location_mode": "precise",
                "persistence": "persistent",
                "interval": 2,
                "display": 5,
                "fuzz": 40,
            }
        }
    )
    _place(session, clock, hid, seek)
    run_for(session, clock, 2)
    pin = session.state.seeker_reveals[0]
    fix = session.state.players[seek].location
    assert fix is not None
    assert pin.radius_m == 0
    assert pin.lat == fix.point.lat
    assert pin.lon == fix.point.lon
    run_for(session, clock, 30)
    assert len(session.state.seeker_reveals) == 1
    assert session.state.seeker_reveals[0].player_id == seek


def test_hot_cold_gives_hiders_a_seeker_hint_and_seekers_still_see_hiders() -> None:
    session, clock, hid, seek = _pair(
        {
            "reveal_fuzzy": {
                "location_mode": "fuzzy",
                "interval": 30,
                "fuzz": 0,
                "hints_enabled": True,
                "hints_persistence": "persistent",
                "hints_interval": 2,
            },
            "reveal_seekers": {
                "location_mode": "hot_cold",
                "interval": 2,
                "display": 5,
                "hints_persistence": "persistent",
                "hints_interval": 2,
            },
        }
    )
    # 30 m due north stays inside the hot band. The 40 m edge rounds over it.
    session.record_location(hid, reading(meters(100, 100), clock))
    session.record_location(seek, reading(meters(100, 130), clock))
    run_for(session, clock, 2)
    assert session.state.seeker_reveals == []
    hider_hint = session.state.players[hid].hint
    seeker_hint = session.state.players[seek].hint
    assert hider_hint is not None
    assert hider_hint["name"] == "Jordan"
    assert hider_hint["band"] == "hot"
    assert hider_hint["meters"] == 30
    assert hider_hint["bearing_deg"] == 0
    assert seeker_hint is not None
    assert seeker_hint["name"] == "Riley"
    assert seeker_hint["bearing_deg"] == 180


def test_seeker_interval_is_independent_of_hider_reveals() -> None:
    session, clock, hid, seek = _pair(
        {
            "reveal_fuzzy": {"interval": 10, "display": 5, "fuzz": 0},
            "reveal_seekers": {
                "location_mode": "fuzzy",
                "interval": 2,
                "display": 5,
                "fuzz": 0,
            },
        }
    )
    _place(session, clock, hid, seek)
    run_for(session, clock, 2)
    assert session.state.reveals == []
    assert len(session.state.seeker_reveals) == 1
    assert session.state.seeker_reveals[0].player_id == seek
    assert session.state.last_reveal_at_s is None
    assert session.state.last_seeker_reveal_at_s == 2


def test_jammer_clears_the_hider_hint() -> None:
    session, clock, hid, seek = _pair(
        {
            "reveal_seekers": {
                "location_mode": "fuzzy",
                "interval": 30,
                "hints_enabled": True,
                "hints_persistence": "persistent",
                "hints_interval": 5,
            }
        }
    )
    _place(session, clock, hid, seek)
    session.state.players[hid].points = 300
    run_for(session, clock, 1)
    assert session.state.players[hid].hint is not None
    session.purchase(hid, "jammer")
    session.tick()
    assert session.state.players[hid].hint is None


def test_seeker_reveal_does_not_pulse_during_head_start() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 10, "seeker_lock": "locked_map"},
            "reveal_seekers": {
                "location_mode": "precise",
                "interval": 2,
                "display": 5,
                "fuzz": 0,
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
    _place(session, clock, hid, seek)
    run_for(session, clock, 8)
    assert session.state.phase == "head_start"
    assert session.state.seeker_reveals == []
    assert session.state.last_seeker_reveal_at_s is None
    run_for(session, clock, 2)
    assert session.state.phase == "active"
    assert len(session.state.seeker_reveals) == 1
    assert session.state.last_seeker_reveal_at_s is not None
