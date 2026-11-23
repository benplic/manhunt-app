from datetime import timedelta
from uuid import uuid4

from app.engine.arena import ArenaZone, PolygonShape, ZoneKind
from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.engine.views import build_view
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import gazebo_arena, meters, reading, run_for, two_player_hunt


def test_out_of_bounds_countdown_eliminates_a_hider() -> None:
    session, clock, hider, _seeker = two_player_hunt(
        overrides={"zone_policy": {"oob_countdown": 3}}
    )
    session.record_location(hider, reading(meters(100, -80), clock, accuracy=5))
    run_for(session, clock, 1)
    assert session.state.players[hider].bounds_phase == "warning"
    run_for(session, clock, 1)
    assert session.state.players[hider].bounds_phase == "countdown"
    assert session.state.players[hider].bounds_remaining_s == 3
    run_for(session, clock, 3)
    assert session.state.players[hider].status == "eliminated"
    events = session.drain_events()
    event = next(event for event in events if event.type == "out_of_bounds")
    assert "out of bounds" in event.text.lower()
    assert event.payload["announcement"] == "player_tagged_out_of_bounds"
    assert event.payload["subject_name"] == "Riley"


def test_out_of_bounds_does_not_eliminate_during_head_start() -> None:
    """Walk-in / bad first GPS must not end the hunt before seekers can move."""
    session, clock, hider, seeker = two_player_hunt(
        overrides={
            "head_start": {"enabled": True, "duration": 30},
            "zone_policy": {"oob_countdown": 3},
            "win": {"condition": "either"},
        }
    )
    # two_player_hunt already burned 1s of head start; stay in head_start.
    assert session.state.phase == "head_start"
    session.record_location(hider, reading(meters(100, -80), clock, accuracy=5))
    session.record_location(seeker, reading(meters(100, 100), clock, accuracy=5))
    run_for(session, clock, 10)
    assert session.state.phase == "head_start"
    assert session.state.players[hider].status == "active"
    assert session.state.players[hider].bounds_phase == "warning"
    assert session.state.result is None


def test_out_zone_beats_a_safe_zone_that_covers_the_same_ground() -> None:
    session, clock, hider, seeker = two_player_hunt()
    arena = gazebo_arena()
    arena.zones.append(
        ArenaZone(
            id=uuid4(),
            name="Shed",
            kind=ZoneKind.OUT_OF_BOUNDS,
            shape=PolygonShape(
                vertices=[meters(90, 90), meters(120, 90), meters(120, 120), meters(90, 120)]
            ),
        )
    )
    session.state.arena = arena
    # Gazebo safe circle is centered near (100, 101). This point is in both.
    session.record_location(hider, reading(meters(100, 101), clock))
    session.record_location(seeker, reading(meters(100, 102), clock))
    run_for(session, clock, 1)
    assert session.state.players[hider].safe_zone_id is None
    assert session.state.players[hider].bounds_phase == "warning"
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert session.state.players[hider].status == "eliminated"

    # A hider in the same safe circle, clear of the shed, is still protected.
    session, clock, hider, seeker = two_player_hunt()
    session.state.arena = gazebo_arena()
    session.record_location(hider, reading(meters(100, 101), clock))
    session.record_location(seeker, reading(meters(100, 102), clock))
    run_for(session, clock, 1)
    assert session.state.players[hider].safe_zone_id is not None
    try:
        token = make_qr_token(
            game_id=session.state.game_id,
            hider_id=hider,
            expires_at=clock.now() + timedelta(seconds=30),
            key=session.qr_signing_key,
        )
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
        raise AssertionError("expected the safe zone to block the tag")
    except GameRuleError as exc:
        assert exc.code == ErrorCode.TARGET_IN_SAFE_ZONE


def test_safe_remove_after_drops_protection_and_arena_zones() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={
            "head_start": {"enabled": True, "duration": 1},
            "signal_loss": {"silence": 600},
            "zone_policy": {"safe_visit": 120, "safe_remove_after": 1},
        }
    )
    session.state.arena = gazebo_arena()
    session.record_location(hider, reading(meters(100, 101), clock))
    session.record_location(seeker, reading(meters(100, 102), clock))
    run_for(session, clock, 1)
    assert session.state.players[hider].safe_zone_id is not None
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    try:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
        raise AssertionError("expected the safe zone to block the tag")
    except GameRuleError as exc:
        assert exc.code == ErrorCode.TARGET_IN_SAFE_ZONE

    # After one active minute past head start, safes are gone.
    for _ in range(60):
        session.record_location(hider, reading(meters(100, 101), clock))
        session.record_location(seeker, reading(meters(100, 102), clock))
        run_for(session, clock, 1)
    assert session.state.players[hider].safe_zone_id is None
    view = build_view(session, hider)
    assert all(zone["kind"] != "safe" for zone in view["arena"]["zones"])
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert session.state.players[hider].status == "eliminated"


def test_seeker_outside_is_revealed_until_they_return() -> None:
    session, clock, hider, seeker = two_player_hunt(
        overrides={"zone_policy": {"oob_countdown": 15}}
    )
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, -80), clock))
    run_for(session, clock, 1)
    hider_view = build_view(session, hider)
    pin = next(p for p in hider_view["players"] if p["player_id"] == str(seeker))
    assert pin["location"] is not None
    assert pin["location"]["kind"] == "exact"
    session.record_location(seeker, reading(meters(100, 100), clock))
    run_for(session, clock, 1)
    hider_view = build_view(session, hider)
    pin = next(p for p in hider_view["players"] if p["player_id"] == str(seeker))
    assert pin["location"] is None
    assert session.state.players[seeker].status == "active"
