from datetime import timedelta

import pytest

from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import meters, reading, two_player_hunt


def test_far_gps_pair_cannot_be_saved_by_a_fake_uwb_reading() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.record_location(hider, reading(meters(160, 160), clock))
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, seeker_range=1, hider_range=1))
    assert exc.value.code == ErrorCode.NOT_IN_PAIRING_RANGE


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
