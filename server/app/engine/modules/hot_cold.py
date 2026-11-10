"""Distance band and bearing toward hiders. Jammer mutes it."""

from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.geo import ACCURACY_CUTOFF_M, bearing_deg, distance_m

if TYPE_CHECKING:
    from app.engine.session import GameSession
    from app.engine.state import PlayerState

from app.engine.modules.base import BaseModule

BANDS = (
    (15, "burning"),
    (40, "hot"),
    (80, "warm"),
    (150, "cool"),
    (1_000_000, "cold"),
)


class HotColdModule(BaseModule):
    module_id: ClassVar[str] = "hot_cold"

    def on_tick(self, s: GameSession) -> None:
        enabled = bool(self.settings.get("enabled", True))
        interval = int(self.settings.get("interval", 5))
        jammed = s.state.jammer_until_s is not None
        for player in s.state.players.values():
            # A jammer clears the dock on this tick, without waiting for the interval.
            if not enabled or jammed or s.state.phase != "active" or player.role != "seeker":
                player.hint = None
                player.hint_at_s = None
                continue
            if (
                player.hint is not None
                and player.hint_at_s is not None
                and s.state.game_elapsed_s - player.hint_at_s < interval
            ):
                continue
            player.hint = _hint_for(s, player)
            player.hint_at_s = s.state.game_elapsed_s


def _hint_for(s: GameSession, seeker: PlayerState) -> dict | None:
    if seeker.location is None or seeker.location.accuracy_m > ACCURACY_CUTOFF_M:
        return None
    best = None
    target_name = None
    target_point = None
    for other in s.state.players.values():
        if other.player_id == seeker.player_id:
            continue
        if other.role != "hider" or other.status != "active":
            continue
        loc = other.last_precise or other.location
        if loc is None or loc.accuracy_m > ACCURACY_CUTOFF_M:
            continue
        dist = distance_m(seeker.location.point, loc.point)
        if best is None or dist < best:
            best = dist
            target_name = other.display_name
            target_point = loc.point
    if best is None or target_point is None:
        return None
    band = "cold"
    for limit, name in BANDS:
        if best <= limit:
            band = name
            break
    return {
        "band": band,
        "meters": int(best),
        "name": target_name,
        "bearing_deg": bearing_deg(seeker.location.point, target_point),
    }
