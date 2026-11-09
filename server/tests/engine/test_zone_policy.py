from app.engine.views import build_view
from tests.engine.helpers import meters, reading, run_for, two_player_hunt


def test_out_of_bounds_countdown_eliminates_a_hider() -> None:
    session, clock, hider, _seeker = two_player_hunt(
        overrides={"zone_policy": {"oob_countdown": 3}}
    )
    session.record_location(hider, reading(meters(100, -80), clock, accuracy=5))
    run_for(session, clock, 1)
    assert session.state.players[hider].bounds_phase == "warning"
    run_for(session, clock, 1)
    assert session.state.players[hider].bounds_phase == "countdown"
    assert session.state.players[hider].bounds_remaining_s == 3
    run_for(session, clock, 3)
    assert session.state.players[hider].status == "eliminated"
    events = session.drain_events()
    assert any("out of bounds" in e.text.lower() for e in events)


def test_seeker_outside_is_revealed_until_they_return() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"zone_policy": {"oob_countdown": 15}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, -80), clock))
    run_for(session, clock, 1)
    hider_view = build_view(session, hider)
    pin = next(p for p in hider_view["players"] if p["player_id"] == str(seeker))
    assert pin["location"] is not None
    assert pin["location"]["kind"] == "exact"
    session.record_location(seeker, reading(meters(100, 100), clock))
    run_for(session, clock, 1)
    hider_view = build_view(session, hider)
    pin = next(p for p in hider_view["players"] if p["player_id"] == str(seeker))
    assert pin["location"] is None
    assert session.state.players[seeker].status == "active"
