from datetime import timedelta

import pytest

from app.engine.arena import ArenaZone, PolygonShape, ZoneKind
from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import gazebo_arena, meters, reading, run_for, two_player_hunt


def test_uwb_tag_requires_both_ranges() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"method": "uwb", "radius_m": 2}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    session.set_uwb_token(seeker, "s" * 16)
    session.set_uwb_token(hider, "h" * 16)
    assert session.report_uwb_range(seeker, hider, 1) is True
    assert session.report_uwb_range(hider, seeker, 9) is True
    with pytest.raises(GameRuleError) as exc:
        session.claim_uwb(seeker, hider)
    assert exc.value.code == ErrorCode.NOT_IN_RANGE
    assert session.report_uwb_range(hider, seeker, 1) is True
    session.claim_uwb(seeker, hider)
    assert session.state.players[hider].status == "eliminated"


def test_uwb_preset_still_accepts_qr_with_pairing() -> None:
    """QR stays the fallback when method is uwb (spec §5.6)."""
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"method": "uwb", "radius_m": 2}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert session.state.players[hider].status == "eliminated"


def test_non_finite_uwb_range_is_dropped() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"method": "uwb", "radius_m": 2}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    session.set_uwb_token(seeker, "s" * 16)
    session.set_uwb_token(hider, "h" * 16)
    assert session.report_uwb_range(seeker, hider, float("nan")) is False
    assert session.report_uwb_range(seeker, hider, float("inf")) is False
    assert hider not in session.state.players[seeker].uwb_ranges


def test_uwb_range_for_a_non_peer_is_dropped() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"method": "uwb", "radius_m": 2}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    session.set_uwb_token(seeker, "s" * 16)
    session.set_uwb_token(hider, "h" * 16)
    stranger = __import__("uuid").uuid4()
    assert session.report_uwb_range(seeker, stranger, 1) is False
    assert stranger not in session.state.players[seeker].uwb_ranges
    session.record_location(hider, reading(meters(100, 160), clock))
    assert session.report_uwb_range(seeker, hider, 1) is False
    assert hider not in session.state.players[seeker].uwb_ranges


def test_uwb_token_and_range_are_not_inputs() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"method": "uwb", "radius_m": 2}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    token = "s" * 16
    session.set_uwb_token(seeker, token)
    session.set_uwb_token(hider, "h" * 16)
    session.report_uwb_range(seeker, hider, 1)
    blob = str(session.state.inputs)
    assert token not in blob
    assert "uwb_token" not in blob


def test_stale_uwb_ranges_are_not_in_range() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"tag_policy": {"method": "uwb", "radius_m": 2}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    session.set_uwb_token(seeker, "s" * 16)
    session.set_uwb_token(hider, "h" * 16)
    session.report_uwb_range(seeker, hider, 1)
    session.report_uwb_range(hider, seeker, 1)
    run_for(session, clock, 4)
    with pytest.raises(GameRuleError) as exc:
        session.claim_uwb(seeker, hider)
    assert exc.value.code == ErrorCode.NOT_IN_RANGE


def test_undo_tag_restores_the_hider() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    session.undo_tag()
    assert session.state.players[hider].status == "active"
    assert session.state.phase == "active"


def test_spawn_zone_lock_banners_a_seeker_who_leaves() -> None:
    arena = gazebo_arena()
    arena.zones.append(
        ArenaZone(
            id=__import__("uuid").uuid4(),
            name="Spawn",
            kind=ZoneKind.SEEKER_SPAWN,
            shape=PolygonShape(
                vertices=[meters(0, 0), meters(40, 0), meters(40, 40), meters(0, 40)]
            ),
        )
    )
    session, clock, hider, seeker = two_player_hunt(
        overrides={"head_start": {"enabled": True, "duration": 5, "seeker_lock": "spawn_zone"}}
    )
    session.state.arena = arena
    session.state.phase = "head_start"
    session.record_location(seeker, reading(meters(150, 150), clock))
    run_for(session, clock, 1)
    assert any(b.title == "Stay in spawn" for b in session.state.banners)
    from app.engine.views import build_view

    view = build_view(session, seeker)
    assert view["seeker_lock"] == "spawn_zone"
    assert view["spawn_lock"]["outside"] is True
    assert view["spawn_lock"]["zones"][0]["kind"] == "seeker_spawn"


def test_seeker_inside_the_spawn_zone_is_not_locked_out() -> None:
    arena = gazebo_arena()
    arena.zones.append(
        ArenaZone(
            id=__import__("uuid").uuid4(),
            name="Spawn",
            kind=ZoneKind.SEEKER_SPAWN,
            shape=PolygonShape(
                vertices=[meters(0, 0), meters(40, 0), meters(40, 40), meters(0, 40)]
            ),
        )
    )
    session, clock, _hider, seeker = two_player_hunt(
        overrides={"head_start": {"enabled": True, "duration": 30, "seeker_lock": "spawn_zone"}}
    )
    session.state.arena = arena
    session.record_location(seeker, reading(meters(10, 10), clock))
    run_for(session, clock, 1)
    assert not any(b.title == "Stay in spawn" for b in session.state.banners)
    from app.engine.views import build_view

    view = build_view(session, seeker)
    assert view["spawn_lock"]["outside"] is False
    assert view["spawn_lock"]["zones"]


def test_locked_map_has_no_spawn_lock() -> None:
    session, _clock, _hider, seeker = two_player_hunt(
        overrides={"head_start": {"enabled": True, "duration": 30, "seeker_lock": "locked_map"}}
    )
    from app.engine.views import build_view

    view = build_view(session, seeker)
    assert view["phase"] == "head_start"
    assert view["seeker_lock"] == "locked_map"
    assert view["spawn_lock"] is None
    assert view["tag_method"] == "qr"
