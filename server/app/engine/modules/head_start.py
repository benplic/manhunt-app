from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.arena import ZoneKind
from app.engine.geo import ACCURACY_CUTOFF_M
from app.engine.modules.base import BaseModule
from app.engine.modules.zone_policy import _covered_by_out_zone, _in_zone
from app.engine.state import Banner, PlayerState

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
            if player.role != "seeker" or player.status != "active":
                continue
            if _seeker_in_spawn(player, spawns, s.state.arena.zones):
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
                    detail="The countdown waits until every seeker is inside the spawn zone.",
                    player_id=player.player_id,
                )
            )


def spawn_clock_held(s: GameSession) -> bool:
    """True while the head-start countdown must not run.

    Spawn lock waits until every active seeker has a precise fix inside a
    spawn zone. An out zone on that same ground does not count. Leaving
    pauses the clock. Locked-map head start, and a map with no spawn, run now.
    """
    if s.state.phase != "head_start":
        return False
    if s.module_settings("head_start").get("seeker_lock") != "spawn_zone":
        return False
    spawns = [z for z in s.state.arena.zones if z.kind == ZoneKind.SEEKER_SPAWN]
    if not spawns:
        return False
    seekers = [
        player
        for player in s.state.players.values()
        if player.role == "seeker" and player.status == "active"
    ]
    if not seekers:
        return False
    return any(not _seeker_in_spawn(player, spawns, s.state.arena.zones) for player in seekers)


def _seeker_in_spawn(player: PlayerState, spawns: list, zones: list) -> bool:
    reading = player.location
    if reading is None or reading.accuracy_m > ACCURACY_CUTOFF_M:
        return False
    point = reading.point
    # Out of bounds wins over the spawn polygon, including a hole we cannot store.
    if _covered_by_out_zone(point, zones):
        return False
    return any(_in_zone(point, zone) for zone in spawns)
