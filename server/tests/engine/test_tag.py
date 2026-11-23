from datetime import timedelta

from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from tests.engine.helpers import meters, reading, two_player_hunt


def _token(session, clock, hider):
    return make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )


def test_qr_tag_succeeds_when_players_are_far_apart() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(seeker, reading(meters(100, 100), clock, accuracy=5))
    session.record_location(hider, reading(meters(400, 100), clock, accuracy=5))
    session.claim_tag(TagClaim(seeker, hider, qr_token=_token(session, clock, hider)))
    assert session.state.players[hider].status == "eliminated"


def test_qr_tag_succeeds_with_fuzzy_gps() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(seeker, reading(meters(100, 100), clock, accuracy=80))
    session.record_location(hider, reading(meters(105, 100), clock, accuracy=80))
    session.claim_tag(TagClaim(seeker, hider, qr_token=_token(session, clock, hider)))
    assert session.state.players[hider].status == "eliminated"


def test_qr_tag_succeeds_without_a_fix() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.claim_tag(TagClaim(seeker, hider, qr_token=_token(session, clock, hider)))
    assert session.state.players[hider].status == "eliminated"


def test_a_sprint_is_kept_and_a_teleport_is_rejected() -> None:
    from app.engine.session import movement_too_fast

    session, clock, _hider, seeker = two_player_hunt()
    first = reading(meters(100, 100), clock)
    assert movement_too_fast(session.state.players[seeker], first) is False
    session.record_location(seeker, first)
    clock.advance(2)
    jog = reading(meters(110, 100), clock)
    assert movement_too_fast(session.state.players[seeker], jog) is False
    session.record_location(seeker, jog)
    clock.advance(1)
    teleport = reading(meters(400, 100), clock)
    assert movement_too_fast(session.state.players[seeker], teleport) is True


def test_rejected_teleport_still_refreshes_presence() -> None:
    """Browser GPS noise must not look like silence when the jump is rejected."""
    from app.engine.session import movement_too_fast, note_presence

    session, clock, _hider, seeker = two_player_hunt()
    first = reading(meters(100, 100), clock)
    session.record_location(seeker, first)
    pinned = session.state.players[seeker].location
    clock.advance(1)
    teleport = reading(meters(400, 100), clock)
    assert movement_too_fast(session.state.players[seeker], teleport) is True
    note_presence(session.state.players[seeker], teleport.recorded_at)
    player = session.state.players[seeker]
    assert player.location is pinned
    assert abs(player.location.lat - first.lat) < 1e-9
    assert player.last_location_at == teleport.recorded_at


def test_qr_tag_eliminates_a_nearby_hider() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.drain_events()
    session.record_location(seeker, reading(meters(100, 100), clock))
    session.record_location(hider, reading(meters(100, 101), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert session.state.players[hider].status == "eliminated"
    assert session.state.players[seeker].points == 25
    assert session.state.players[seeker].points_earned == 25
    assert session.state.phase == "ended"
    assert session.state.result.winner == "seekers"
    event = next(event for event in session.drain_events() if event.type == "tag")
    assert event.payload["announcement"] == "player_tagged"
    assert event.payload["subject_name"] == "Riley"


def test_qr_tag_conversion_emits_the_tagged_hider_name() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"result": "convert"}}
    )
    session.drain_events()

    session.claim_tag(TagClaim(seeker, hider, qr_token=_token(session, clock, hider)))

    assert session.state.players[hider].role == "seeker"
    event = next(event for event in session.drain_events() if event.type == "tag")
    assert event.payload["announcement"] == "player_tagged"
    assert event.payload["subject_name"] == "Riley"
