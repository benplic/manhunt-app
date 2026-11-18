from datetime import timedelta

from app.engine.arena import ArenaZone, PolygonShape, ZoneKind
from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from tests.engine.helpers import gazebo_arena, meters, reading, run_for, two_player_hunt


def test_undo_tag_reverses_others_tagged_award() -> None:
    from uuid import uuid4

    from tests.engine.helpers import make_session, run_for

    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 1},
            "signal_loss": {"silence": 60},
        }
    )
    tagged = uuid4()
    survivor = uuid4()
    seeker = uuid4()
    session.add_player(tagged, "Tagged", is_host=True)
    session.add_player(survivor, "Survivor", is_host=False)
    session.add_player(seeker, "Seeker", is_host=False)
    session.set_role(tagged, "hider")
    session.set_role(survivor, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    run_for(session, clock, 1)
    session.record_location(tagged, reading(meters(100, 100), clock))
    session.record_location(survivor, reading(meters(120, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=tagged,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    pre_points = session.state.players[survivor].points
    pre_earned = session.state.players[survivor].points_earned
    session.claim_tag(TagClaim(seeker, tagged, qr_token=token))
    assert session.state.players[survivor].points == pre_points + 15
    assert session.state.players[survivor].points_earned == pre_earned + 15
    session.undo_tag()
    assert session.state.players[survivor].points == pre_points
    assert session.state.players[survivor].points_earned == pre_earned


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
    pre_points = session.state.players[seeker].points
    pre_earned = session.state.players[seeker].points_earned
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert session.state.players[seeker].points_earned == pre_earned + 25
    session.undo_tag()
    assert session.state.players[hider].status == "active"
    assert session.state.phase == "active"
    assert session.state.players[seeker].points == pre_points
    assert session.state.players[seeker].points_earned == pre_earned


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