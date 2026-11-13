from __future__ import annotations

import math
from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.geo import ACCURACY_CUTOFF_M, offset_m
from app.engine.modules.base import BaseModule
from app.engine.state import RevealPin

if TYPE_CHECKING:
    from app.engine.session import GameSession

_PERSISTENT_EXTRA_S = 60 * 60 * 24 * 365


def publish_hints(s: GameSession) -> None:
    from app.engine.modules.hot_cold import refresh_hints

    refresh_hints(s, after_pulse=True)


def _hints_active(settings: dict) -> bool:
    mode = str(settings.get("location_mode", "fuzzy"))
    if mode == "hot_cold":
        return True
    if mode == "precise":
        return False
    return bool(settings.get("hints_enabled", True))


class RevealFuzzyModule(BaseModule):
    module_id: ClassVar[str] = "reveal_fuzzy"

    def on_tick(self, s: GameSession) -> None:
        now = s.state.game_elapsed_s
        live = [r for r in s.state.reveals if r.expires_at_game_s > now]
        s.state.reveals = live
        if s.state.phase not in {"active", "head_start"}:
            return

        settings = self.settings
        location_mode = str(settings.get("location_mode", "fuzzy"))
        persistence = str(settings.get("persistence", "timed"))
        interval = int(settings.get("interval", 60))
        display = int(settings.get("display", 10))
        fuzz = float(settings.get("fuzz", 30))
        hints_persistence = str(settings.get("hints_persistence", "persistent"))

        last = s.state.last_reveal_at_s
        if last is None:
            if now < interval:
                return
        elif now - last < interval:
            return
        s.state.last_reveal_at_s = now

        if location_mode == "hot_cold":
            s.state.reveals = []
            if _hints_active(settings) and hints_persistence == "timed":
                until = now + display
                republish = True
                for player in s.state.players.values():
                    if player.role != "seeker":
                        continue
                    prev = player.hint_until_s
                    if prev is not None and now >= prev:
                        player.hint = None
                        player.hint_at_s = None
                        republish = False
                    player.hint_until_s = until
                if republish:
                    publish_hints(s)
            s.emit("reveal", {"text": "Hider pins are up."}, tone="info")
            return

        expiry = (
            now + _PERSISTENT_EXTRA_S
            if persistence == "persistent"
            else now + display
        )

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

            if location_mode == "precise":
                pin = origin
                radius = 0.0
            elif fuzz <= 0:
                pin = origin
                radius = 0.0
            else:
                angle = s.rng.random() * 6.283185307179586
                dist = s.rng.random() * fuzz
                pin = offset_m(
                    origin,
                    north_m=dist * math.cos(angle),
                    east_m=dist * math.sin(angle),
                )
                radius = fuzz

            s.state.reveals = [
                r for r in s.state.reveals if r.player_id != player.player_id
            ]
            s.state.reveals.append(
                RevealPin(
                    reveal_id=uuid4(),
                    player_id=player.player_id,
                    lat=pin.lat,
                    lon=pin.lon,
                    radius_m=max(radius, 0),
                    expires_at_game_s=expiry,
                )
            )

        if _hints_active(settings) and hints_persistence == "timed":
            until = now + display
            republish = True
            for player in s.state.players.values():
                if player.role != "seeker":
                    continue
                prev = player.hint_until_s
                if prev is not None and now >= prev:
                    player.hint = None
                    player.hint_at_s = None
                    republish = False
                player.hint_until_s = until
            if republish:
                publish_hints(s)

        s.emit("reveal", {"text": "Hider pins are up."}, tone="info")
