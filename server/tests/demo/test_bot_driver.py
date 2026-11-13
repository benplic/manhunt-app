"""Tests for demo BotDriver: determinism, shrink steering, spawn hold, chase/tag, modes."""

from uuid import UUID

from app.demo.bots import BotDriver
from app.demo.state import DemoState
from app.engine.arena import (
    PLAY_CIRCLE_STEPS,
    Arena,
    ArenaZone,
    CircleShape,
    PolygonShape,
    ZoneKind,
)
from app.engine.geo import circle_sample_ring, contains, distance_m, offset_m
from app.engine.state import LocationReading
from tests.engine.helpers import make_session, meters


def _circle_demo_arena(radius_m: float = 180.0) -> Arena:
    center = meters(500, 500)
    spawn = [
        offset_m(center, -5, -15),
        offset_m(center, -5, 15),
        offset_m(center, -35, 15),
        offset_m(center, -35, -15),
    ]
    safe = ArenaZone(
        id=UUID("00000000-0000-0000-0000-00000000e002"),
        name="Safe",
        kind=ZoneKind.SAFE,
        shape=CircleShape(center=offset_m(center, 50, 0), radius_m=22.0),
    )
    spawn_zone = ArenaZone(
        id=UUID("00000000-0000-0000-0000-00000000e001"),
        name="Spawn",
        kind=ZoneKind.SEEKER_SPAWN,
        shape=PolygonShape(vertices=spawn),
    )
    return Arena(
        id=UUID("00000000-0000-0000-0000-00000000e000"),
        name="Demo Circle",
        boundary=circle_sample_ring(center, radius_m, steps=PLAY_CIRCLE_STEPS),
        boundary_circle=CircleShape(center=center, radius_m=radius_m),
        zones=[spawn_zone, safe],
    )


def _setup_demo(
    seed: int = 42,
    *,
    method: str = "qr",
    win_condition: str = "either",
    tag_radius_m: float = 2.0,
):
    session, clock = make_session(
        arena=_circle_demo_arena(),
        seed=seed,
        overrides={
            "head_start": {"enabled": True, "duration": 10, "seeker_lock": "spawn_zone"},
            "zone_shrink": {"enabled": True, "every": 1, "shrink_to": 65, "min_radius_m": 60},
            "tag_policy": {"method": method, "radius_m": tag_radius_m, "pairing_m": 30.0},
            "signal_loss": {"silence": 20},
            "zone_policy": {"oob_countdown": 5},
            "win": {"condition": win_condition, "time_limit": 30},
        },
    )
    human = UUID("00000000-0000-0000-0000-00000000a001")
    bot_seeker = UUID("00000000-0000-0000-0000-00000000b001")
    bot_hider = UUID("00000000-0000-0000-0000-00000000b002")
    session.add_player(human, "Human", is_host=True)
    session.add_player(bot_seeker, "Bot Seeker", is_host=False)
    session.add_player(bot_hider, "Bot Hider", is_host=False)
    session.set_role(human, "seeker")
    session.set_role(bot_seeker, "seeker")
    session.set_role(bot_hider, "hider")
    session.demo = DemoState.initial(session, bot_ids=[bot_seeker, bot_hider])
    BotDriver.seed_positions(session)
    return session, clock, human, bot_seeker, bot_hider


def test_bot_driver_is_deterministic_with_same_seed() -> None:
    s1, c1, _, bs1, bh1 = _setup_demo(seed=123)
    s2, c2, _, bs2, bh2 = _setup_demo(seed=123)
    s1.start()
    s2.start()

    for _ in range(25):
        c1.advance(1)
        c2.advance(1)
        s1.tick()
        s2.tick()
        BotDriver.step(s1)
        BotDriver.step(s2)

    assert s1.state.players[bs1].location.point == s2.state.players[bs2].location.point
    assert s1.state.players[bh1].location.point == s2.state.players[bh2].location.point


def test_bots_hold_spawn_during_head_start_and_stay_inside_shrinking_circle() -> None:
    session, clock, _, bot_seeker, bot_hider = _setup_demo(
        seed=9, win_condition="time_limit", tag_radius_m=0.0
    )
    session.start()
    spawn_poly = session.state.arena.zones[0].shape.vertices  # type: ignore[union-attr]
    initial_hider = session.state.players[bot_hider].location.point  # type: ignore[union-attr]

    for _ in range(10):
        clock.advance(1)
        session.tick()
        BotDriver.step(session)
        if session.state.phase == "head_start":
            seeker_pt = session.state.players[bot_seeker].location.point  # type: ignore[union-attr]
            assert contains(seeker_pt, spawn_poly)

    moved_hider = session.state.players[bot_hider].location.point  # type: ignore[union-attr]
    assert distance_m(initial_hider, moved_hider) > 5.0

    # Run past two 1-minute shrink steps; auto bots steer inward and avoid OOB elimination.
    for _ in range(135):
        clock.advance(1)
        session.tick()
        BotDriver.step(session)
        if session.state.phase == "ended":
            break

    assert session.state.arena.boundary_circle is not None
    assert session.state.arena.boundary_circle.radius_m < 130.0
    for pid in (bot_seeker, bot_hider):
        p = session.state.players[pid]
        assert p.bounds_phase == "inside"


def test_bot_seeker_chases_and_tags_hider_even_with_human_seeker() -> None:
    for method in ("qr", "uwb"):
        session, clock, _, bot_seeker, bot_hider = _setup_demo(seed=77, method=method)
        session.start()
        # Advance past 10s head start
        for _ in range(10):
            clock.advance(1)
            session.tick()
            BotDriver.step(session)
        assert session.state.phase == "active"

        # Place hider 25m away from seeker so chase + tag finishes quickly.
        center = session.state.arena.boundary_circle.center  # type: ignore[union-attr]
        session.set_synthetic_location(
            bot_seeker,
            LocationReading(
                lat=center.lat, lon=center.lon, accuracy_m=5.0, recorded_at=clock.now()
            ),
        )
        near = offset_m(center, 0, -25)
        session.set_synthetic_location(
            bot_hider,
            LocationReading(lat=near.lat, lon=near.lon, accuracy_m=5.0, recorded_at=clock.now()),
        )

        tagged = False
        for _ in range(40):
            clock.advance(1)
            session.tick()
            BotDriver.step(session)
            if session.state.players[bot_hider].status == "eliminated":
                tagged = True
                break

        assert tagged is True
        assert any(e.type == "tag" for e in session.state.event_log)


def test_bot_seeker_safe_zone_refusal_does_not_crash() -> None:
    session, clock, _, bot_seeker, bot_hider = _setup_demo(seed=5)
    session.start()
    for _ in range(10):
        clock.advance(1)
        session.tick()
        BotDriver.step(session)

    safe_center = session.state.arena.zones[1].shape.center  # type: ignore[union-attr]
    session.set_synthetic_location(
        bot_hider,
        LocationReading(
            lat=safe_center.lat, lon=safe_center.lon, accuracy_m=5.0, recorded_at=clock.now()
        ),
    )
    session.set_synthetic_location(
        bot_seeker,
        LocationReading(
            lat=safe_center.lat, lon=safe_center.lon, accuracy_m=5.0, recorded_at=clock.now()
        ),
    )
    for _ in range(18):
        clock.advance(1)
        session.tick()
        BotDriver.step(session)

    assert session.state.players[bot_hider].status == "active"


def test_bot_modes_go_dark_oob_and_human_walk() -> None:
    session, clock, human, bot_seeker, bot_hider = _setup_demo(seed=11)
    session.start()
    for _ in range(10):
        clock.advance(1)
        session.tick()
        BotDriver.step(session)

    assert session.demo is not None
    center = session.state.arena.boundary_circle.center  # type: ignore[union-attr]
    target = offset_m(center, 20, 0)
    session.set_synthetic_location(
        human,
        LocationReading(lat=center.lat, lon=center.lon, accuracy_m=5.0, recorded_at=clock.now()),
    )
    session.demo.human_targets[human] = target
    session.demo.bot_modes[bot_hider] = "go_dark"
    session.demo.bot_modes[bot_seeker] = "oob"

    for _ in range(25):
        clock.advance(1)
        session.tick()
        BotDriver.step(session)

    human_pt = session.state.players[human].location.point  # type: ignore[union-attr]
    assert distance_m(human_pt, target) < 1.0
    assert human not in session.demo.human_targets
    assert session.state.players[bot_hider].status == "signal_lost"
    assert session.state.players[bot_seeker].oob_revealed is True
