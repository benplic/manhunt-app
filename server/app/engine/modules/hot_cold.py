"""Distance band and bearing toward the other role. Jammer mutes it."""

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


def _reveal_settings(s: GameSession) -> dict:
    reveal = s.module_settings("reveal_fuzzy")
    if "location_mode" in reveal or "hints_enabled" in reveal:
        return reveal
    return s.module_settings("hot_cold")


def _hints_active(settings: dict) -> bool:
    mode = str(settings.get("location_mode", "fuzzy"))
    if mode == "off":
        return False
    if mode == "hot_cold":
        return True
    if mode == "precise":
        return False
    if "location_mode" in settings or "hints_enabled" in settings:
        return bool(settings.get("hints_enabled", True))
    return bool(settings.get("enabled", True))


def _audience_settings(s: GameSession, audience: str) -> dict:
    """Seeker hints read Reveal. Hider hints read Seeker reveal, and missing means Off."""
    if audience == "seeker":
        return _reveal_settings(s)
    settings = s.module_settings("reveal_seekers")
    if "location_mode" not in settings:
        return {"location_mode": "off"}
    return settings


def _clear_hint(player: PlayerState) -> None:
    player.hint = None
    player.hint_at_s = None
    player.hint_until_s = None


def refresh_hints(
    s: GameSession, *, after_pulse: bool = False, audience: str | None = None
) -> None:
    """Refresh one role, or both. Each role keeps its own settings and hint window."""
    roles = ("seeker", "hider") if audience is None else (audience,)
    for role in roles:
        _refresh_audience(s, role, after_pulse=after_pulse)


def _refresh_audience(s: GameSession, audience: str, *, after_pulse: bool) -> None:
    settings = _audience_settings(s, audience)
    if not _hints_active(settings):
        for player in s.state.players.values():
            if player.role == audience:
                _clear_hint(player)
        return

    hints_persistence = str(settings.get("hints_persistence", "persistent"))
    interval = int(
        settings.get(
            "hints_interval",
            settings.get("interval", 5),
        )
    )
    jammed = s.state.jammer_until_s is not None
    now = s.state.game_elapsed_s
    opponent = "seeker" if audience == "hider" else "hider"

    for player in s.state.players.values():
        if player.role != audience:
            continue
        if jammed or s.state.phase != "active":
            _clear_hint(player)
            continue

        if hints_persistence == "timed":
            until = player.hint_until_s
            if until is None or now >= until:
                player.hint = None
                player.hint_at_s = None
                continue
            if player.hint is None and after_pulse:
                player.hint = _hint_for(s, player, opponent_role=opponent)
                player.hint_at_s = now
            continue

        if (
            player.hint is not None
            and player.hint_at_s is not None
            and now - player.hint_at_s < interval
        ):
            continue
        player.hint = _hint_for(s, player, opponent_role=opponent)
        player.hint_at_s = now


class HotColdModule(BaseModule):
    module_id: ClassVar[str] = "hot_cold"

    def on_tick(self, s: GameSession) -> None:
        refresh_hints(s)


def _hint_for(s: GameSession, viewer: PlayerState, *, opponent_role: str) -> dict | None:
    if viewer.location is None or viewer.location.accuracy_m > ACCURACY_CUTOFF_M:
        return None
    best = None
    target_name = None
    target_point = None
    for other in s.state.players.values():
        if other.player_id == viewer.player_id:
            continue
        if other.role != opponent_role or other.status != "active":
            continue
        loc = other.last_precise or other.location
        if loc is None or loc.accuracy_m > ACCURACY_CUTOFF_M:
            continue
        dist = distance_m(viewer.location.point, loc.point)
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
        "bearing_deg": bearing_deg(viewer.location.point, target_point),
    }
