"""Server-side bot AI driver for demo sessions."""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.engine.geo import GeoPoint
from app.engine.state import LocationReading

if TYPE_CHECKING:
    from app.engine.session import GameSession


def _arena_center(session: GameSession) -> GeoPoint:
    circle = session.state.arena.boundary_circle
    if circle is not None:
        return circle.center
    boundary = session.state.arena.boundary
    lat = sum(p.lat for p in boundary) / max(1, len(boundary))
    lon = sum(p.lon for p in boundary) / max(1, len(boundary))
    return GeoPoint(lat=lat, lon=lon)


class BotDriver:
    @staticmethod
    def seed_positions(session: GameSession) -> None:
        """Place players inside the sample arena before the first tick."""
        center = _arena_center(session)
        now = session.clock.now()
        for player in session.state.players.values():
            if player.location is not None:
                continue
            session.set_synthetic_location(
                player.player_id,
                LocationReading(
                    lat=center.lat,
                    lon=center.lon,
                    accuracy_m=5.0,
                    recorded_at=now,
                ),
            )

    @staticmethod
    def step(session: GameSession) -> None:
        """Advance virtual humans and bots for one engine tick."""
        _ = session
