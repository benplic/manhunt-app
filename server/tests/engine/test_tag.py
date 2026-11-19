from datetime import timedelta

import pytest

from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import meters, reading, two_player_hunt


def test_inflated_accuracy_does_not_stretch_pairing() -> None:
    session, clock, hider, seeker = two_player_hunt()
    # Nearby phones with accuracy worse than the 30 m cutoff cannot tag.
    session.record_location(seeker, reading(meters(100, 100), clock, accuracy=35))
    session.record_location(hider, reading(meters(105, 100), clock, accuracy=35))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert exc.value.code == ErrorCode.NOT_IN_PAIRING_RANGE
    assert "fuzzy" in exc.value.message.lower()


def test_accuracy_bonus_cap_keeps_pairing_tight() -> None:
    session, clock, hider, seeker = two_player_hunt()
    # 50 m apart. Pairing is 30. Only 5 m of accuracy bonus per phone.
    session.record_location(seeker, reading(meters(100, 100), clock, accuracy=25))
    session.record_location(hider, reading(meters(150, 100), clock, accuracy=25))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert exc.value.code == ErrorCode.NOT_IN_PAIRING_RANGE
    assert "closer" in exc.value.message.lower()


def test_tag_rejects_missing_fix_with_a_clear_message() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(seeker, reading(meters(100, 100), clock))
    # Hider never sent a fix.
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert exc.value.code == ErrorCode.NOT_IN_PAIRING_RANGE
    assert "location" in exc.value.message.lower() or "fix" in exc.value.message.lower()


def test_tag_rejects_distance_with_get_closer_copy() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(seeker, reading(meters(100, 100), clock, accuracy=5))
    session.record_location(hider, reading(meters(160, 100), clock, accuracy=5))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert exc.value.code == ErrorCode.NOT_IN_PAIRING_RANGE
    assert "closer" in exc.value.message.lower()


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
