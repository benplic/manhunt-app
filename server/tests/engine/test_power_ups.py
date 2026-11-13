from datetime import timedelta

import pytest

from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import meters, reading, run_for, two_player_hunt


def _qr(session, clock, hider):
    return make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )


def test_second_shield_purchase_is_on_cooldown() -> None:
    session, clock, hider, seeker = two_player_hunt(overrides={"signal_loss": {"silence": 600}})
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.state.players[hider].points = 200
    session.purchase(hider, "shield")
    with pytest.raises(GameRuleError) as exc:
        session.purchase(hider, "shield")
    assert exc.value.code == ErrorCode.COOLING_DOWN
    run_for(session, clock, 60)
    session.purchase(hider, "shield")


def test_ghost_skips_the_next_reveal() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"reveal_fuzzy": {"interval": 2, "display": 10, "fuzz": 30}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.state.players[hider].points = 100
    session.purchase(hider, "ghost")
    run_for(session, clock, 1)
    assert all(p.player_id != hider for p in session.state.reveals)


def test_decoy_outside_the_play_area_is_rejected() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.state.players[hider].points = 200
    with pytest.raises(GameRuleError) as exc:
        session.purchase(hider, "decoy", lat=1.0, lon=1.0)
    assert exc.value.code == ErrorCode.TARGET_OUTSIDE


def test_shield_blocks_tags_until_lockdown() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    session.state.players[hider].points = 200
    session.state.players[seeker].points = 200
    session.purchase(hider, "shield")
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=_qr(session, clock, hider)))
    assert exc.value.code == ErrorCode.TARGET_SHIELDED
    session.purchase(seeker, "lockdown")
    # Shield still blocks; lockdown only disables safe zones.
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=_qr(session, clock, hider)))
    assert exc.value.code == ErrorCode.TARGET_SHIELDED


def test_scan_radar_and_jammer() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.state.players[hider].points = 300
    session.state.players[seeker].points = 300
    session.purchase(seeker, "scan")
    assert session.state.reveals
    session.purchase(hider, "radar")
    session.purchase(hider, "jammer")
    from app.engine.views import build_view

    hider_view = build_view(session, hider)
    assert any(p["location"] for p in hider_view["players"] if p["player_id"] == str(seeker))
    session.tick()
    seeker_view = build_view(session, seeker)
    assert seeker_view["you"].get("hint") is None
