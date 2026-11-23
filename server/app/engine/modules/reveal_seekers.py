"""Seeker pulses for hiders. Independent of reveal_fuzzy."""

from __future__ import annotations

import math
from typing import TYPE_CHECKING, Any, ClassVar
from uuid import uuid4

from app.engine.geo import ACCURACY_CUTOFF_M, offset_m
from app.engine.modules.base import BaseModule
from app.engine.modules.hot_cold import _clear_hint, _hints_active
from app.engine.state import RevealPin

if TYPE_CHECKING:
    from app.engine.session import GameSession

# Same horizon as hider pins: a persistent pin outlives any hunt.
_PERSISTENT_EXTRA_S = 60 * 60 * 24 * 365


def _publish_hider_hints(s: GameSession) -> None:
    from app.engine.modules.hot_cold import refresh_hints

    refresh_hints(s, after_pulse=True, audience="hider")


def _republish_timed_hider_hints(
    s: GameSession,
    settings: dict[str, Any],
    hints_persistence: str,
    now: float,
    display: int,
) -> None:
    """Extend hider hint windows. A window that already closed is not republished."""
    if not (_hints_active(settings) and hints_persistence == "timed"):
        return
    until = now + display
    republish = True
    for player in s.state.players.values():
        if player.role != "hider":
            continue
        prev = player.hint_until_s
        if prev is not None and now >= prev:
            player.hint = None
            player.hint_at_s = None
            republish = False
        player.hint_until_s = until
    if republish:
        _publish_hider_hints(s)


class RevealSeekersModule(BaseModule):
    module_id: ClassVar[str] = "reveal_seekers"

    def on_tick(self, s: GameSession) -> None:
        now = s.state.game_elapsed_s
        live = [r for r in s.state.seeker_reveals if r.expires_at_game_s > now]
        s.state.seeker_reveals = live
        # No seeker pings during head start, same rule as hider reveals.
        if s.state.phase != "active":
            return

        settings = self.settings
        location_mode = str(settings.get("location_mode", "off"))
        # Off returns before any RNG draw so hider pin offsets stay stable.
        if location_mode == "off":
            for player in s.state.players.values():
                if player.role == "hider":
                    _clear_hint(player)
            return

        persistence = str(settings.get("persistence", "timed"))
        interval = int(settings.get("interval", 60))
        display = int(settings.get("display", 10))
        fuzz = float(settings.get("fuzz", 30))
        hints_persistence = str(settings.get("hints_persistence", "persistent"))

        last = s.state.last_seeker_reveal_at_s
        if last is None:
            if now < interval:
                return
        elif now - last < interval:
            return
        s.state.last_seeker_reveal_at_s = now

        if location_mode == "hot_cold":
            s.state.seeker_reveals = []
            _republish_timed_hider_hints(s, settings, hints_persistence, now, display)
            return

        expiry = now + _PERSISTENT_EXTRA_S if persistence == "persistent" else now + display

        pins_added = 0
        for player in s.state.players.values():
            if player.role != "seeker" or player.status != "active":
                continue
            # Ghost and decoy are hider tools. A seeker pulse uses that seeker's fix.
            reading = player.last_precise or player.location
            if reading is None or reading.accuracy_m > ACCURACY_CUTOFF_M:
                continue
            origin = reading.point

            if location_mode == "precise" or fuzz <= 0:
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

            s.state.seeker_reveals = [
                r for r in s.state.seeker_reveals if r.player_id != player.player_id
            ]
            s.state.seeker_reveals.append(
                RevealPin(
                    reveal_id=uuid4(),
                    player_id=player.player_id,
                    lat=pin.lat,
                    lon=pin.lon,
                    radius_m=max(radius, 0),
                    expires_at_game_s=expiry,
                )
            )
            pins_added += 1

        _republish_timed_hider_hints(s, settings, hints_persistence, now, display)

        if pins_added > 0:
            s.emit("reveal", {"text": "Seeker pins are up."}, tone="info")
