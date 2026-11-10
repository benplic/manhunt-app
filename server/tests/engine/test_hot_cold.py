"""Hot/cold band, bearing, update interval, and jammer."""

import pytest

from app.errors import ErrorCode
from tests.engine.helpers import meters, reading, run_for, two_player_hunt


def test_hint_bearing_due_north_is_zero() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"hot_cold": {"enabled": True, "interval": 5}}
    )
    session.record_location(seeker, reading(meters(100, 100), clock))
    # 30 m north stays inside the "hot" band even if the flat projection is a hair over.
    session.record_location(hider, reading(meters(100, 130), clock))
    session.tick()
    hint = session.state.players[seeker].hint
    assert hint is not None
    assert hint["bearing_deg"] == 0
    assert hint["band"] == "hot"
    assert hint["name"] == "Riley"


def test_hint_holds_until_the_interval_elapses() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"hot_cold": {"enabled": True, "interval": 5}}
    )
    session.record_location(seeker, reading(meters(100, 100), clock))
    session.record_location(hider, reading(meters(100, 140), clock))
    session.tick()
    held = session.state.players[seeker].hint["meters"]
    session.record_location(hider, reading(meters(100, 110), clock))
    session.tick()
    assert session.state.players[seeker].hint["meters"] == held
    run_for(session, clock, 4)
    assert session.state.players[seeker].hint["meters"] != held


def test_jammer_clears_the_hint_on_the_next_tick() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"hot_cold": {"enabled": True, "interval": 5}}
    )
    session.record_location(seeker, reading(meters(100, 100), clock))
    session.record_location(hider, reading(meters(100, 140), clock))
    session.state.players[hider].points = 300
    session.tick()
    assert session.state.players[seeker].hint is not None
    session.purchase(hider, "jammer")
    session.tick()
    assert session.state.players[seeker].hint is None


def test_interval_below_two_seconds_is_rejected() -> None:
    from app.errors import ApiError
    from app.presets.classic import validate_overrides

    with pytest.raises(ApiError) as exc:
        validate_overrides({"hot_cold": {"interval": 1}})
    assert exc.value.code == ErrorCode.VALIDATION_FAILED
