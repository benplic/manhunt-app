"""Distance band and bearing toward hiders. Jammer mutes it."""

from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.geo import ACCURACY_CUTOFF_M, distance_m

if TYPE_CHECKING:
    from app.engine.session import GameSession

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
        jammed = s.state.jammer_until_s is not None
        for player in s.state.players.values():
            player.hint = None
            if not enabled or jammed:
                continue
            if s.state.phase != "active":
                continue
            if player.role != "seeker" and not (
                player.role == "hider"
                and player.radar_until_s
                and s.state.game_elapsed_s < player.radar_until_s
            ):
                # Seekers always get a hint; hiders only with Radar (handled in views).
                if player.role != "seeker":
                    continue
            if player.tracker_until_s is None and player.role == "seeker":
                # Default hot/cold is on for seekers unless the host disabled the module.
                pass
            hint = _hint_for(s, player)
            player.hint = hint


def _hint_for(s: GameSession, seeker) -> dict | None:
    if seeker.location is None or seeker.location.accuracy_m > ACCURACY_CUTOFF_M:
        return None
    best = None
    target_name = None
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
    if best is None:
        return None
    band = "cold"
    for limit, name in BANDS:
        if best <= limit:
            band = name
            break
    return {"band": band, "meters": int(best), "name": target_name}
