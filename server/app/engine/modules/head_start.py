from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.arena import ZoneKind
from app.engine.modules.base import BaseModule
from app.engine.modules.zone_policy import _in_zone
from app.engine.state import Banner

if TYPE_CHECKING:
    from app.engine.session import GameSession


class HeadStartModule(BaseModule):
    module_id: ClassVar[str] = "head_start"

    @property
    def enabled(self) -> bool:
        return bool(self.settings.get("enabled", True))

    @property
    def duration(self) -> int:
        return int(self.settings.get("duration", 60))

    def on_start(self, s: GameSession) -> None:
        if self.enabled and self.duration > 0:
            s.state.phase = "head_start"
            s.state.phase_remaining_s = self.duration
        else:
            s.state.phase = "active"
            s.state.phase_remaining_s = None

    def on_tick(self, s: GameSession) -> None:
        if s.state.phase != "head_start":
            return
        remaining = max(0, self.duration - s.state.game_elapsed_s)
        s.state.phase_remaining_s = remaining
        if remaining <= 0:
            s.state.phase = "active"
            s.state.phase_remaining_s = None
            s.emit("head_start_ended", {"text": "Head start ended. Seekers released."})
            return
        if self.settings.get("seeker_lock") != "spawn_zone":
            return
        spawns = [z for z in s.state.arena.zones if z.kind == ZoneKind.SEEKER_SPAWN]
        if not spawns:
            return
        for player in s.state.players.values():
            if player.role != "seeker" or player.location is None:
                continue
            if any(_in_zone(player.location.point, zone) for zone in spawns):
                s.state.banners = [
                    b
                    for b in s.state.banners
                    if not (b.player_id == player.player_id and b.title == "Stay in spawn")
                ]
                continue
            already = any(
                b.player_id == player.player_id and b.title == "Stay in spawn"
                for b in s.state.banners
            )
            if already:
                continue
            s.state.banners.append(
                Banner(
                    banner_id=uuid4(),
                    tone="warning",
                    title="Stay in spawn",
                    detail="Seekers wait in the spawn zone until head start ends.",
                    player_id=player.player_id,
                )
            )
