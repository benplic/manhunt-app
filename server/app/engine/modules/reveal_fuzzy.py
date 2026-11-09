from __future__ import annotations

import math
from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.geo import ACCURACY_CUTOFF_M, offset_m
from app.engine.modules.base import BaseModule
from app.engine.state import RevealPin

if TYPE_CHECKING:
    from app.engine.session import GameSession


class RevealFuzzyModule(BaseModule):
    module_id: ClassVar[str] = "reveal_fuzzy"

    def on_tick(self, s: GameSession) -> None:
        live = [r for r in s.state.reveals if r.expires_at_game_s > s.state.game_elapsed_s]
        s.state.reveals = live
        if s.state.phase not in {"active", "head_start"}:
            return
        interval = int(self.settings.get("interval", 60))
        display = int(self.settings.get("display", 10))
        fuzz = float(self.settings.get("fuzz", 30))
        last = s.state.last_reveal_at_s
        if last is None:
            # First reveal after `interval` seconds of game time in a started match.
            if s.state.game_elapsed_s < interval:
                return
        elif s.state.game_elapsed_s - last < interval:
            return
        s.state.last_reveal_at_s = s.state.game_elapsed_s
        for player in s.state.players.values():
            if player.role != "hider" or player.status != "active":
                continue
            if getattr(player, "ghost_next_reveal", False):
                player.ghost_next_reveal = False  # type: ignore[attr-defined]
                continue
            if player.decoy_point is not None:
                origin = player.decoy_point
                player.decoy_point = None
            else:
                reading = player.last_precise or player.location
                if reading is None or reading.accuracy_m > ACCURACY_CUTOFF_M:
                    continue
                origin = reading.point
            if fuzz <= 0:
                pin = origin
            else:
                # Seeded offset inside the fuzz radius. True position stays inside the circle.
                angle = s.rng.random() * 6.283185307179586
                dist = s.rng.random() * fuzz
                pin = offset_m(
                    origin,
                    north_m=dist * math.cos(angle),
                    east_m=dist * math.sin(angle),
                )
            s.state.reveals.append(
                RevealPin(
                    reveal_id=uuid4(),
                    player_id=player.player_id,
                    lat=pin.lat,
                    lon=pin.lon,
                    radius_m=max(fuzz, 0),
                    expires_at_game_s=s.state.game_elapsed_s + display,
                )
            )
        s.emit("reveal", {"text": "Hider pins are up."}, tone="info")
