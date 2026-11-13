from uuid import uuid4

import pytest

from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import make_session, run_for


def test_head_start_honors_duration_then_unlocks() -> None:
    session, clock = make_session(overrides={"head_start": {"duration": 12}})
    hid = uuid4()
    seek = uuid4()
    session.add_player(hid, "Riley", True)
    session.add_player(seek, "Jordan", False)
    session.set_role(hid, "hider")
    session.set_role(seek, "seeker")
    session.start()
    assert session.state.phase == "head_start"
    run_for(session, clock, 11)
    assert session.state.phase == "head_start"
    run_for(session, clock, 1)
    assert session.state.phase == "active"


def test_disabled_head_start_starts_active_and_needs_both_roles() -> None:
    session, _clock = make_session(overrides={"head_start": {"enabled": False}})
    a = uuid4()
    b = uuid4()
    session.add_player(a, "Riley", True)
    session.add_player(b, "Jordan", False)
    with pytest.raises(GameRuleError) as exc:
        session.start()
    assert exc.value.code == ErrorCode.NEED_BOTH_ROLES
    session.assign_roles_random(1)
    session.start()
    assert session.state.phase == "active"


def test_spawn_lock_holds_head_start_until_seekers_are_inside_and_pauses_if_they_leave() -> None:
    from app.engine.arena import ArenaZone, PolygonShape, ZoneKind
    from app.engine.views import build_view
    from tests.engine.helpers import meters, reading

    session, clock = make_session(
        overrides={
            "head_start": {"enabled": True, "duration": 10, "seeker_lock": "spawn_zone"},
            "win": {"time_limit": 30},
        }
    )
    session.state.arena.zones.append(
        ArenaZone(
            id=uuid4(),
            name="Spawn",
            kind=ZoneKind.SEEKER_SPAWN,
            shape=PolygonShape(
                vertices=[meters(0, 0), meters(40, 0), meters(40, 40), meters(0, 40)]
            ),
        )
    )
    hider = uuid4()
    seeker = uuid4()
    other = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.add_player(other, "Quinn", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.set_role(other, "seeker")
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(150, 150), clock))
    session.record_location(other, reading(meters(10, 10), clock))
    session.start()
    limit = session.state.time_limit_remaining_s
    run_for(session, clock, 8)
    assert session.state.phase == "head_start"
    assert session.state.game_elapsed_s == 0
    assert session.state.phase_remaining_s == 10
    assert session.state.time_limit_remaining_s == limit
    view = build_view(session, seeker)
    assert view["spawn_lock"]["holding"] is True
    assert view["spawn_lock"]["outside"] is True
    assert build_view(session, other)["spawn_lock"]["outside"] is False

    session.record_location(seeker, reading(meters(12, 12), clock))
    run_for(session, clock, 4)
    assert session.state.phase == "head_start"
    assert session.state.game_elapsed_s == 4
    assert session.state.phase_remaining_s == 6
    assert build_view(session, seeker)["spawn_lock"]["holding"] is False

    # Leaving mid-countdown freezes the clock until every seeker is back.
    session.record_location(other, reading(meters(90, 90), clock))
    run_for(session, clock, 5)
    assert session.state.phase == "head_start"
    assert session.state.game_elapsed_s == 4
    assert session.state.phase_remaining_s == 6

    session.record_location(other, reading(meters(8, 8), clock))
    run_for(session, clock, 5)
    assert session.state.phase == "head_start"
    assert session.state.game_elapsed_s == 9
    run_for(session, clock, 1)
    assert session.state.phase == "active"
    assert session.state.game_elapsed_s == 10


def test_seeker_standing_in_an_out_zone_does_not_start_head_start() -> None:
    from app.engine.arena import ArenaZone, PolygonShape, ZoneKind
    from tests.engine.helpers import meters, reading

    session, clock = make_session(
        overrides={"head_start": {"enabled": True, "duration": 6, "seeker_lock": "spawn_zone"}}
    )
    session.state.arena.zones.extend(
        [
            ArenaZone(
                id=uuid4(),
                name="Spawn",
                kind=ZoneKind.SEEKER_SPAWN,
                shape=PolygonShape(
                    vertices=[meters(0, 0), meters(80, 0), meters(80, 80), meters(0, 80)]
                ),
            ),
            ArenaZone(
                id=uuid4(),
                name="Shed",
                kind=ZoneKind.OUT_OF_BOUNDS,
                shape=PolygonShape(
                    vertices=[meters(0, 0), meters(30, 0), meters(30, 30), meters(0, 30)]
                ),
            ),
        ]
    )
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.record_location(hider, reading(meters(100, 100), clock))
    # Inside the spawn polygon, but the out zone covers this corner.
    session.record_location(seeker, reading(meters(10, 10), clock))
    session.start()
    run_for(session, clock, 4)
    assert session.state.phase == "head_start"
    assert session.state.game_elapsed_s == 0
    session.record_location(seeker, reading(meters(50, 50), clock))
    run_for(session, clock, 6)
    assert session.state.phase == "active"


def test_locked_map_head_start_does_not_wait_for_spawn() -> None:
    from app.engine.arena import ArenaZone, PolygonShape, ZoneKind
    from tests.engine.helpers import meters, reading

    session, clock = make_session(
        overrides={"head_start": {"enabled": True, "duration": 3, "seeker_lock": "locked_map"}}
    )
    session.state.arena.zones.append(
        ArenaZone(
            id=uuid4(),
            name="Spawn",
            kind=ZoneKind.SEEKER_SPAWN,
            shape=PolygonShape(
                vertices=[meters(0, 0), meters(20, 0), meters(20, 20), meters(0, 20)]
            ),
        )
    )
    session.add_player(uuid4(), "Riley", True)
    seeker = uuid4()
    session.add_player(seeker, "Jordan", False)
    session.assign_roles_random(1)
    session.record_location(seeker, reading(meters(100, 100), clock))
    session.start()
    run_for(session, clock, 3)
    assert session.state.phase == "active"


def test_pause_freezes_the_head_start_clock() -> None:
    session, clock = make_session(overrides={"head_start": {"duration": 5}})
    session.add_player(uuid4(), "Riley", True)
    session.add_player(uuid4(), "Jordan", False)
    session.assign_roles_random(1)
    session.start()
    session.pause()
    run_for(session, clock, 20)
    assert session.state.phase == "paused"
    session.resume()
    assert session.state.phase == "head_start"
    run_for(session, clock, 5)
    assert session.state.phase == "active"
