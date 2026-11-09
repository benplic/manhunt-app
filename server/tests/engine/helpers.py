"""Shared engine fixtures. Coordinates match the Swift Fixtures.meters helper."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.engine.arena import Arena, ArenaZone, CircleShape, ZoneKind
from app.engine.clock import FakeClock
from app.engine.geo import GeoPoint
from app.engine.session import GameSession
from app.engine.state import LocationReading
from app.presets.classic import classic_preset


def meters(x: float, y: float) -> GeoPoint:
    return GeoPoint(lat=y / 111_320, lon=x / 111_320)


def square() -> Arena:
    return Arena(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        name="Square",
        boundary=[
            meters(0, 0),
            meters(200, 0),
            meters(200, 200),
            meters(0, 200),
        ],
        zones=[],
    )


def run_for(session: GameSession, clock: FakeClock, seconds: int) -> None:
    for _ in range(seconds):
        clock.advance(1)
        session.tick()


def reading(point: GeoPoint, clock: FakeClock, accuracy: float = 5) -> LocationReading:
    return LocationReading(
        lat=point.lat,
        lon=point.lon,
        accuracy_m=accuracy,
        recorded_at=clock.now(),
    )


def make_session(
    *,
    overrides: dict | None = None,
    seed: int = 1,
    clock: FakeClock | None = None,
    join_code: str = "PARK42",
    arena: Arena | None = None,
) -> tuple[GameSession, FakeClock]:
    clock = clock or FakeClock(datetime(2023, 11, 14, 12, 0, tzinfo=UTC))
    preset = classic_preset(overrides)
    session = GameSession(
        game_id=uuid4(),
        arena=arena or square(),
        preset=preset,
        clock=clock,
        seed=seed,
        join_code=join_code,
        qr_signing_key="test-qr-key",
    )
    return session, clock


def two_player_hunt(overrides: dict | None = None) -> tuple[GameSession, FakeClock, UUID, UUID]:
    merged = {
        "head_start": {"enabled": True, "duration": 1},
        "signal_loss": {"silence": 60},
        "reveal_fuzzy": {"interval": 30},
    }
    if overrides:
        for key, value in overrides.items():
            merged.setdefault(key, {}).update(value)
    session, clock = make_session(overrides=merged)
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", is_host=True)
    session.add_player(seeker, "Jordan", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    run_for(session, clock, 1)
    return session, clock, hider, seeker


def gazebo_arena() -> Arena:
    arena = square()
    arena.zones = [
        ArenaZone(
            id=uuid4(),
            name="Gazebo",
            kind=ZoneKind.SAFE,
            shape=CircleShape(center=meters(100, 101), radius_m=15),
        )
    ]
    return arena
