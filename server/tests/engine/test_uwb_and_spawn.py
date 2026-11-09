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
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert exc.value.code == ErrorCode.NOT_IN_RANGE
    with pytest.raises(GameRuleError) as exc:
        session.claim_tag(TagClaim(seeker, hider, qr_token=token, seeker_range=1, hider_range=9))
    assert exc.value.code == ErrorCode.NOT_IN_RANGE
    session.claim_tag(TagClaim(seeker, hider, qr_token=token, seeker_range=1, hider_range=1))
    assert session.state.players[hider].status == "eliminated"


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
