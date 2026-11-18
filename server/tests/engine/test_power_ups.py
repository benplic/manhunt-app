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
    from app.engine.views import build_view

    # Lockdown is shared so hiders can fade safe zones on the map.
    assert "lockdown" in build_view(session, hider)["you"]["effects"]
    assert "lockdown" in build_view(session, seeker)["you"]["effects"]


def test_scan_radar_and_jammer() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.state.players[hider].points = 300
    session.state.players[seeker].points = 300
    session.purchase(seeker, "scan")
    assert session.state.reveals
    assert session.state.reveals[0].radius_m == 30
    session.purchase(hider, "radar")
    session.purchase(hider, "jammer")
    from app.engine.views import build_view

    hider_view = build_view(session, hider)
    assert any(p["location"] for p in hider_view["players"] if p["player_id"] == str(seeker))
    session.tick()
    seeker_view = build_view(session, seeker)
    assert seeker_view["you"].get("hint") is None


def test_scan_uses_power_ups_radius_and_pin_count() -> None:
    from uuid import uuid4

    from tests.engine.helpers import make_session

    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 1},
            "signal_loss": {"silence": 60},
            "power_ups": {
                "scan_enabled": True,
                "scan_cost": 5,
                "scan_radius_m": 55,
                "scan_count": 2,
            },
            "reveal_fuzzy": {"fuzz": 5, "interval": 30},
        }
    )
    hider = uuid4()
    second = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", is_host=True)
    session.add_player(second, "Casey", is_host=False)
    session.add_player(seeker, "Jordan", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(second, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    run_for(session, clock, 1)
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(second, reading(meters(120, 120), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.state.players[seeker].points = 50
    before = len(session.state.reveals)
    session.purchase(seeker, "scan")
    pins = session.state.reveals[before:]
    assert len(pins) == 2
    assert {p.player_id for p in pins} == {hider, second}
    assert all(p.radius_m == 55 for p in pins)


def test_disabled_power_is_rejected_and_a_custom_cost_is_charged() -> None:
    session, clock, hider, seeker = two_player_hunt(
        {
            "power_ups": {
                "enabled": True,
                "ghost_enabled": False,
                "scan_enabled": True,
                "scan_cost": 10,
            }
        }
    )
    session.state.players[hider].points = 100
    with pytest.raises(GameRuleError):
        session.purchase(hider, "ghost")
    assert session.state.players[hider].points == 100
    session.state.players[seeker].points = 10
    session.purchase(seeker, "scan")
    assert session.state.players[seeker].points == 0
    assert session.state.players[seeker].points_earned == 0


def test_tracker_purchase_rejected_in_hot_cold_mode() -> None:
    session, clock, hider, seeker = two_player_hunt(
        {
            "reveal_fuzzy": {
                "location_mode": "hot_cold",
                "persistence": "timed",
                "hints_enabled": False,
            }
        }
    )
    session.state.players[seeker].points = 200
    with pytest.raises(GameRuleError) as exc:
        session.purchase(seeker, "tracker")
    assert exc.value.code == ErrorCode.WRONG_PHASE
    assert "tracker" in exc.value.message.lower()
    assert session.state.players[seeker].points == 200
    assert session.state.players[seeker].tracker_until_s is None


def test_tracker_purchase_rejected_when_location_is_persistent() -> None:
    session, clock, hider, seeker = two_player_hunt(
        {
            "reveal_fuzzy": {
                "location_mode": "fuzzy",
                "persistence": "persistent",
                "hints_enabled": True,
            }
        }
    )
    session.state.players[seeker].points = 200
    with pytest.raises(GameRuleError) as exc:
        session.purchase(seeker, "tracker")
    assert exc.value.code == ErrorCode.WRONG_PHASE
    assert "tracker" in exc.value.message.lower()
    assert session.state.players[seeker].points == 200
    assert session.state.players[seeker].tracker_until_s is None


def test_tracker_purchase_allowed_on_timed_fuzzy() -> None:
    session, clock, hider, seeker = two_player_hunt(
        {
            "reveal_fuzzy": {
                "location_mode": "fuzzy",
                "persistence": "timed",
                "hints_enabled": False,
            }
        }
    )
    session.state.players[seeker].points = 200
    session.purchase(seeker, "tracker")
    assert session.state.players[seeker].points == 150
    assert session.state.players[seeker].tracker_until_s is not None


def test_tracker_chip_marked_unavailable_in_hot_cold_view() -> None:
    from app.engine.views import build_view

    session, clock, hider, seeker = two_player_hunt(
        {"reveal_fuzzy": {"location_mode": "hot_cold", "persistence": "timed"}}
    )
    view = build_view(session, seeker)
    tracker = next(p for p in view["power_ups"] if p["id"] == "tracker")
    assert tracker["available"] is False
