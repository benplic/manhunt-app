import pytest

from app.engine.modules.base import TagClaim
from app.errors import ErrorCode, GameRuleError
from app.schemas.modules import SCHEMAS
from tests.engine.helpers import meters, reading, two_player_hunt


def test_tag_policy_schema_has_no_uwb_method() -> None:
    method = SCHEMAS["tag_policy"]["fields"]["method"]
    assert method["values"] == ["qr"]
    assert "uwb" not in method["values"]


def test_claim_without_qr_token_is_rejected_even_with_ranges() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(40, 40), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(
            TagClaim(seeker, hider, seeker_range=1.0, hider_range=1.0, qr_token=None)
        )
    assert exc.value.code == ErrorCode.TOKEN_INVALID