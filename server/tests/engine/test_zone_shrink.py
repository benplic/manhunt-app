from uuid import UUID, uuid4

from app.engine.arena import PLAY_CIRCLE_STEPS, Arena, CircleShape
from app.engine.geo import circle_sample_ring, distance_m
from app.engine.views import build_view
from tests.engine.helpers import make_session, meters, reading, run_for


def _circle_arena(radius_m: float = 400.0) -> Arena:
    center = meters(500, 500)
    return Arena(
        id=UUID("00000000-0000-0000-0000-000000000002"),
        name="Circle",
        boundary=circle_sample_ring(center, radius_m, steps=PLAY_CIRCLE_STEPS),
        zones=[],
        boundary_circle=CircleShape(center=center, radius_m=radius_m),
    )


def test_zone_shrink_schedule_floor_and_pause_freeze() -> None:
    session, clock = make_session(
        arena=_circle_arena(400.0),
        overrides={
            "head_start": {"enabled": True, "duration": 20},
            "zone_shrink": {
                "enabled": True,
                "every": 1,
                "shrink_to": 50,
                "min_radius_m": 120,
            },
            "win": {"time_limit": 30},
        },
    )
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()

    start_view = build_view(session, hider)
    assert start_view["timers"]["zone"] == {
        "radius_m": 400.0,
        "next_radius_m": 200.0,
        "shrinks_in_s": 80,
    }

    # During head start + first 59s of active, radius stays 400.
    run_for(session, clock, 40)
    session.record_location(hider, reading(meters(500, 500), clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))
    run_for(session, clock, 39)
    assert session.state.arena.boundary_circle is not None
    assert session.state.arena.boundary_circle.radius_m == 400.0

    # Pausing freezes the shrink countdown.
    session.record_location(hider, reading(meters(500, 500), clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))
    session.pause()
    run_for(session, clock, 10)
    assert session.state.arena.boundary_circle.radius_m == 400.0
    assert build_view(session, hider)["timers"]["zone"]["shrinks_in_s"] == 1
    session.resume()

    # Next tick triggers first shrink: 400 -> 200.
    run_for(session, clock, 1)
    session.record_location(hider, reading(meters(500, 500), clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))
    assert session.state.arena.boundary_circle.radius_m == 200.0
    events = [e.type for e in session.drain_events()]
    assert "zone_warning" in events
    assert "zone_shrunk" in events

    mid_view = build_view(session, seeker)
    assert mid_view["timers"]["zone"] == {
        "radius_m": 200.0,
        "next_radius_m": 120.0,
        "shrinks_in_s": 60,
    }

    # Next step clamps at min_radius_m = 120 instead of 100.
    run_for(session, clock, 40)
    session.record_location(hider, reading(meters(500, 500), clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))
    run_for(session, clock, 20)
    assert session.state.arena.boundary_circle.radius_m == 120.0
    floor_view = build_view(session, hider)
    assert floor_view["timers"]["zone"] == {
        "radius_m": 120.0,
        "next_radius_m": None,
        "shrinks_in_s": None,
    }

    # Subsequent intervals keep the floor.
    run_for(session, clock, 40)
    session.record_location(hider, reading(meters(500, 500), clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))
    run_for(session, clock, 80)
    assert session.state.arena.boundary_circle.radius_m == 120.0


def test_hider_near_old_edge_goes_out_of_bounds_after_shrink() -> None:
    session, clock = make_session(
        arena=_circle_arena(400.0),
        overrides={
            "head_start": {"enabled": False},
            "zone_shrink": {
                "enabled": True,
                "every": 1,
                "shrink_to": 50,
                "min_radius_m": 50,
            },
            "zone_policy": {"oob_countdown": 5, "margin_m": 5},
        },
    )
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()

    # Hider stands 300 m east of center: inside 400 m circle, outside 200 m circle.
    spot = meters(800, 500)
    assert abs(distance_m(meters(500, 500), spot) - 300.0) < 0.1
    session.record_location(hider, reading(spot, clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))

    run_for(session, clock, 40)
    session.record_location(hider, reading(spot, clock, accuracy=5))
    session.record_location(seeker, reading(meters(500, 500), clock, accuracy=5))
    run_for(session, clock, 19)
    assert session.state.players[hider].bounds_phase == "inside"
    assert session.state.players[hider].status == "active"

    # Tick 60 shrinks radius to 200 m; keep ticking past warning + 5s OOB countdown.
    run_for(session, clock, 1)
    assert session.state.arena.boundary_circle is not None
    assert session.state.arena.boundary_circle.radius_m == 200.0

    run_for(session, clock, 8)
    assert session.state.players[hider].bounds_phase == "penalized"
    assert session.state.players[hider].status == "eliminated"
