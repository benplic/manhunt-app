from app.engine.views import build_view
from tests.engine.helpers import meters, reading, run_for, two_player_hunt


def test_lobby_has_no_locations() -> None:
    from uuid import uuid4

    from tests.engine.helpers import make_session

    session, _ = make_session()
    hid = uuid4()
    session.add_player(hid, "Riley", True)
    view = build_view(session, hid)
    assert all(p["location"] is None for p in view["players"])


def test_seeker_cannot_see_hider_exact_location() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    session.record_location(seeker, reading(meters(100, 100), clock))
    view = build_view(session, seeker)
    pin = next(p for p in view["players"] if p["player_id"] == str(hider))
    assert pin["location"] is None
    you = next(p for p in view["players"] if p["player_id"] == str(seeker))
    assert you["location"]["kind"] == "exact"


def test_ended_game_shows_everyone() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    session.end("Host ended the hunt.", winner="none")
    view = build_view(session, seeker)
    pin = next(p for p in view["players"] if p["player_id"] == str(hider))
    assert pin["location"] is not None


def test_cooldowns_ride_on_you_only() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    run_for(session, clock, 1)
    session.state.players[hider].points = 200
    session.purchase(hider, "shield")
    hider_view = build_view(session, hider)
    seeker_view = build_view(session, seeker)
    assert hider_view["you"]["cooldowns"].get("shield", 0) > 0
    assert seeker_view["you"]["cooldowns"].get("shield", 0) == 0
    for row in hider_view["players"] + seeker_view["players"]:
        assert "cooldowns" not in row


def test_both_viewers_get_the_same_play_boundary() -> None:
    session, _, hider, seeker = two_player_hunt()
    hider_view = build_view(session, hider)
    seeker_view = build_view(session, seeker)
    assert hider_view["arena"]["boundary"] == seeker_view["arena"]["boundary"]
    assert len(hider_view["arena"]["boundary"]) >= 3
    assert hider_view["arena"]["name"] == session.state.arena.name
    hider_row = next(p for p in hider_view["players"] if p["player_id"] == str(hider))
    assert hider_row["points"] == session.state.players[hider].points


def test_decoy_flag_is_never_on_the_wire() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    run_for(session, clock, 1)
    view = build_view(session, seeker)
    blob = str(view)
    assert "decoy" not in blob.lower()
    assert "is_decoy" not in blob
