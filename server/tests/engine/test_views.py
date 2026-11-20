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


def test_active_effects_show_shield_remaining_to_both_roles() -> None:
    """Seekers and hiders both see how long a live shield has left."""
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    run_for(session, clock, 1)
    session.state.players[hider].points = 200
    session.purchase(hider, "shield")
    hider_view = build_view(session, hider)
    seeker_view = build_view(session, seeker)
    assert "shield" in hider_view["you"]["effects"]
    assert hider_view["you"]["effect_remaining"]["shield"] == 30
    for view in (hider_view, seeker_view):
        shields = [row for row in view["active_effects"] if row["type"] == "shield"]
        assert len(shields) == 1
        assert shields[0]["owner_id"] == str(hider)
        assert shields[0]["display_name"] == "Riley"
        assert shields[0]["remaining_s"] == 30
    run_for(session, clock, 12)
    later = build_view(session, seeker)
    shield = next(row for row in later["active_effects"] if row["type"] == "shield")
    assert shield["remaining_s"] == 18
    run_for(session, clock, 20)
    expired = build_view(session, seeker)
    assert all(row["type"] != "shield" for row in expired["active_effects"])
    assert "shield" not in expired["you"]["effects"]


def test_seeker_does_not_see_attributed_jammer_on_active_effects() -> None:
    """Jammer stays private to the owner; only shield/lockdown are public HUD rows."""
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    run_for(session, clock, 1)
    session.state.players[hider].points = 200
    session.purchase(hider, "jammer")
    hider_view = build_view(session, hider)
    seeker_view = build_view(session, seeker)
    assert "jammer" in hider_view["you"]["effects"]
    assert any(row["type"] == "jammer" for row in hider_view["active_effects"])
    assert all(row["type"] != "jammer" for row in seeker_view["active_effects"])
    assert "jammer" not in seeker_view["you"]["effects"]


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


def test_view_timers_match_phase_reveal_and_pause_for_both_roles() -> None:
    from uuid import uuid4

    from tests.engine.helpers import make_session

    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 15},
            "reveal_fuzzy": {"enabled": True, "interval": 30},
            "win": {"time_limit": 20},
        }
    )
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")

    lobby_view = build_view(session, hider)
    assert lobby_view["timers"] == {
        "head_start_s": 15,
        "time_limit_s": 1200,
        "reveal_interval_s": 30,
        "next_reveal_in_s": 30,
        "zone": None,
    }

    session.start()
    h_start = build_view(session, hider)
    s_start = build_view(session, seeker)
    assert h_start["timers"] == s_start["timers"]
    assert h_start["timers"]["next_reveal_in_s"] == 30

    run_for(session, clock, 10)
    mid = build_view(session, seeker)
    assert mid["timers"]["next_reveal_in_s"] == 20

    session.pause()
    run_for(session, clock, 5)
    paused = build_view(session, seeker)
    assert paused["timers"]["next_reveal_in_s"] == 20
    session.resume()

    run_for(session, clock, 20)
    at_reveal = build_view(session, seeker)
    assert at_reveal["timers"]["next_reveal_in_s"] == 30
    assert "decoy" not in str(at_reveal["timers"]).lower()

