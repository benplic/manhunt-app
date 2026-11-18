from datetime import timedelta
from uuid import UUID, uuid4

import pytest

from app.engine.arena import PLAY_CIRCLE_STEPS, Arena, CircleShape
from app.engine.geo import circle_sample_ring
from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.engine.views import build_view
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import (
    gazebo_arena,
    make_session,
    meters,
    reading,
    run_for,
    two_player_hunt,
)


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


def test_rescue_converts_tagged_seeker_and_grants_immunity() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 1},
            "signal_loss": {"silence": 60},
            "tag_policy": {"result": "convert"},
            "power_ups": {"rescue_enabled": True, "rescue_cost": 120, "rescue_duration": 60},
        }
    )
    hider = uuid4()
    tagged = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", is_host=True)
    session.add_player(tagged, "Casey", is_host=False)
    session.add_player(seeker, "Jordan", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(tagged, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    run_for(session, clock, 1)
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(tagged, reading(meters(100, 101), clock))
    session.record_location(seeker, reading(meters(100, 102), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=tagged,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, tagged, qr_token=token))
    assert session.state.players[tagged].role == "seeker"
    assert session.state.players[tagged].converted_from_hider is True
    view = build_view(session, hider)
    tagged_row = next(p for p in view["players"] if p["player_id"] == str(tagged))
    assert tagged_row["converted_from_hider"] is True

    session.state.players[hider].points = 200
    session.purchase(hider, "rescue", target_player_id=str(tagged))
    rescued = session.state.players[tagged]
    assert rescued.role == "hider"
    assert rescued.converted_from_hider is False
    assert rescued.shield_until_s == session.state.game_elapsed_s + 60
    assert session.state.players[hider].points == 80


def test_rescue_rejects_wrong_role_phase_and_original_seeker() -> None:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 1},
            "signal_loss": {"silence": 60},
            "tag_policy": {"result": "convert"},
        }
    )
    hider = uuid4()
    tagged = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", is_host=True)
    session.add_player(tagged, "Casey", is_host=False)
    session.add_player(seeker, "Jordan", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(tagged, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    # Wrong phase (still head_start until first tick completes? start leaves head_start)
    # After start, phase is head_start; purchase requires active.
    session.state.players[hider].points = 500
    with pytest.raises(GameRuleError) as exc:
        session.purchase(hider, "rescue", target_player_id=str(tagged))
    assert exc.value.code == ErrorCode.WRONG_PHASE

    run_for(session, clock, 1)
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(tagged, reading(meters(100, 101), clock))
    session.record_location(seeker, reading(meters(100, 102), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=tagged,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, tagged, qr_token=token))

    session.state.players[seeker].points = 500
    with pytest.raises(GameRuleError) as exc:
        session.purchase(seeker, "rescue", target_player_id=str(tagged))
    assert exc.value.code == ErrorCode.WRONG_ROLE

    # Original seeker is not a tagged-seeker.
    with pytest.raises(GameRuleError) as exc:
        session.purchase(hider, "rescue", target_player_id=str(seeker))
    assert exc.value.code == ErrorCode.TARGET_NOT_ACTIVE


def test_move_safe_relocates_zone_and_rejects_wrong_role() -> None:
    arena = gazebo_arena()
    zone_id = arena.zones[0].id
    session, clock, hider, seeker = two_player_hunt()
    session.state.arena = arena
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.state.players[seeker].points = 200
    session.state.players[hider].points = 200

    new_center = meters(150, 150)
    session.purchase(
        seeker,
        "move_safe",
        zone_id=str(zone_id),
        lat=new_center.lat,
        lon=new_center.lon,
    )
    moved = next(z for z in session.state.arena.zones if z.id == zone_id)
    assert isinstance(moved.shape, CircleShape)
    assert abs(moved.shape.center.lat - new_center.lat) < 1e-9
    assert abs(moved.shape.center.lon - new_center.lon) < 1e-9
    events = [e.type for e in session.drain_events()]
    assert "safe_moved" in events

    with pytest.raises(GameRuleError) as exc:
        session.purchase(
            hider,
            "move_safe",
            zone_id=str(zone_id),
            lat=new_center.lat,
            lon=new_center.lon,
        )
    assert exc.value.code == ErrorCode.WRONG_ROLE


def test_create_safe_adds_zone_and_rejects_wrong_role_or_outside() -> None:
    session, clock, hider, seeker = two_player_hunt(
        {"power_ups": {"create_safe_radius_m": 20}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(40, 40), clock))
    session.state.players[hider].points = 200
    before = len([z for z in session.state.arena.zones if z.kind.value == "safe"])
    point = meters(80, 80)
    session.purchase(hider, "create_safe", lat=point.lat, lon=point.lon)
    safes = [z for z in session.state.arena.zones if z.kind.value == "safe"]
    assert len(safes) == before + 1
    created = safes[-1]
    assert created.shape.radius_m == 20
    assert abs(created.shape.center.lat - point.lat) < 1e-9
    events = [e.type for e in session.drain_events()]
    assert "safe_created" in events

    with pytest.raises(GameRuleError) as exc:
        session.purchase(seeker, "create_safe", lat=point.lat, lon=point.lon)
    assert exc.value.code == ErrorCode.WRONG_ROLE

    session.state.players[hider].points = 200
    session.state.players[hider].cooldowns.pop("create_safe", None)
    with pytest.raises(GameRuleError) as exc:
        session.purchase(hider, "create_safe", lat=1.0, lon=1.0)
    assert exc.value.code == ErrorCode.TARGET_OUTSIDE


def test_shrink_now_fires_next_shrink_and_shifts_schedule() -> None:
    center = meters(500, 500)
    arena = Arena(
        id=UUID("00000000-0000-0000-0000-000000000002"),
        name="Circle",
        boundary=circle_sample_ring(center, 400.0, steps=PLAY_CIRCLE_STEPS),
        zones=[],
        boundary_circle=CircleShape(center=center, radius_m=400.0),
    )
    session, clock = make_session(
        arena=arena,
        overrides={
            "head_start": {"enabled": False},
            "zone_shrink": {
                "enabled": True,
                "every": 1,
                "shrink_to": 50,
                "min_radius_m": 50,
            },
            "signal_loss": {"silence": 600},
        },
    )
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    session.record_location(hider, reading(meters(500, 500), clock))
    session.record_location(seeker, reading(meters(500, 500), clock))

    before = build_view(session, seeker)["timers"]["zone"]
    assert before["radius_m"] == 400.0
    assert before["next_radius_m"] == 200.0
    assert before["shrinks_in_s"] == 60

    session.state.players[seeker].points = 200
    session.purchase(seeker, "shrink_now")
    assert session.state.arena.boundary_circle is not None
    assert session.state.arena.boundary_circle.radius_m == 200.0
    after = build_view(session, seeker)["timers"]["zone"]
    assert after["radius_m"] == 200.0
    assert after["next_radius_m"] == 100.0
    # Remaining schedule shifted forward: next shrink sooner than a full interval from now.
    assert after["shrinks_in_s"] == 60
    events = [e.type for e in session.drain_events()]
    assert "zone_shrunk" in events

    session.state.players[hider].points = 200
    with pytest.raises(GameRuleError) as exc:
        session.purchase(hider, "shrink_now")
    assert exc.value.code == ErrorCode.WRONG_ROLE
