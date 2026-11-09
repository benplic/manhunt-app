from app.engine.views import build_view
from tests.engine.helpers import meters, reading, run_for, two_player_hunt


def test_silence_shows_the_last_precise_location_to_everyone() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"signal_loss": {"silence": 3}, "head_start": {"duration": 1, "enabled": True}}
    )
    last = meters(40, 40)
    session.record_location(hider, reading(last, clock, accuracy=6))
    run_for(session, clock, 3)
    player = session.state.players[hider]
    assert player.status == "signal_lost"
    assert abs(player.location.lat - last.lat) < 1e-9
    seeker_view = build_view(session, seeker)
    assert any(b["tone"] == "safety" for b in seeker_view["banners"])
    pin = next(p for p in seeker_view["players"] if p["player_id"] == str(hider))
    assert pin["location"] is not None
    assert pin["location"]["kind"] == "last_known"
