"""Server-side purchase pipeline. Mirrors iOS PowerUpRules."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, ClassVar
from uuid import UUID, uuid4

from app.engine.arena import ArenaZone, CircleShape, ZoneKind, clip_arena
from app.engine.geo import GeoPoint, contains
from app.engine.modules.base import BaseModule, TagClaim
from app.engine.modules.effects import add_effect, has_effect
from app.engine.modules.zone_shrink import advance_shrink_schedule, apply_scheduled_shrink
from app.engine.state import RevealPin
from app.errors import ErrorCode, GameRuleError

if TYPE_CHECKING:
    from app.engine.session import GameSession

CATALOG: dict[str, dict[str, Any]] = {
    "ghost": {"role": "hider", "cost": 20, "duration": None, "cooldown": 20, "needs_target": False},
    "decoy": {
        "role": "hider",
        "cost": 40,
        "duration": None,
        "cooldown": 30,
        "needs_target": True,
        "target": "point",
    },
    "radar": {"role": "hider", "cost": 40, "duration": 20, "cooldown": 40, "needs_target": False},
    "jammer": {"role": "hider", "cost": 55, "duration": 60, "cooldown": 90, "needs_target": False},
    "shield": {"role": "hider", "cost": 70, "duration": 30, "cooldown": 60, "needs_target": False},
    "rescue": {
        "role": "hider",
        "cost": 120,
        "duration": 60,
        "cooldown": 90,
        "needs_target": True,
        "target": "player",
    },
    "create_safe": {
        "role": "hider",
        "cost": 110,
        "duration": None,
        "cooldown": 90,
        "needs_target": True,
        "target": "point",
    },
    "scan": {"role": "seeker", "cost": 25, "duration": None, "cooldown": 30, "needs_target": False},
    "tracker": {
        "role": "seeker",
        "cost": 50,
        "duration": 180,
        "cooldown": 60,
        "needs_target": False,
    },
    "lockdown": {
        "role": "seeker",
        "cost": 75,
        "duration": 60,
        "cooldown": 120,
        "needs_target": False,
    },
    "move_safe": {
        "role": "seeker",
        "cost": 110,
        "duration": None,
        "cooldown": 90,
        "needs_target": True,
        "target": "zone_point",
    },
    "shrink_now": {
        "role": "seeker",
        "cost": 100,
        "duration": None,
        "cooldown": 120,
        "needs_target": False,
    },
}


def tracker_allowed(
    reveal: dict[str, Any] | None = None,
    *,
    session: GameSession | None = None,
) -> bool:
    """Tracker is timed hot/cold. Forbid when hints already run always or pins never expire."""
    settings = reveal
    if settings is None:
        if session is None:
            return True
        settings = session.module_settings("reveal_fuzzy")
    mode = str(settings.get("location_mode", "fuzzy"))
    persistence = str(settings.get("persistence", "timed"))
    if mode == "hot_cold":
        return False
    if persistence == "persistent":
        return False
    return True


def resolve_power(s: GameSession, power_id: str) -> dict[str, Any]:
    base = CATALOG.get(power_id)
    if base is None:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, f"Unknown power-up {power_id}.")
    settings = s.module_settings("power_ups")
    if not bool(settings.get("enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Power-ups are off.")
    if not bool(settings.get(f"{power_id}_enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "That power-up is off.")
    if power_id == "tracker" and not tracker_allowed(session=s):
        raise GameRuleError(
            ErrorCode.WRONG_PHASE,
            "Tracker needs timed Fuzzy or Precise location (not Hot/cold or Persistent).",
        )
    spec = dict(base)
    spec["cost"] = int(settings.get(f"{power_id}_cost", base["cost"]))
    if power_id == "rescue":
        spec["duration"] = int(settings.get("rescue_duration", base["duration"]))
    return spec


class PowerUpsModule(BaseModule):
    module_id: ClassVar[str] = "power_ups"

    def check_tag(self, s: GameSession, claim: TagClaim) -> ErrorCode | None:
        hider = s.state.players.get(claim.hider_id)
        if hider is None:
            return ErrorCode.TARGET_NOT_ACTIVE
        if hider.shield_until_s is not None and s.state.game_elapsed_s < hider.shield_until_s:
            return ErrorCode.TARGET_SHIELDED
        if has_effect(s, "shield", owner_id=claim.hider_id):
            return ErrorCode.TARGET_SHIELDED
        return None


def apply_purchase(s: GameSession, player_id, power_id: str, **kwargs: Any) -> None:
    spec = resolve_power(s, power_id)
    player = s.state.players[player_id]
    if s.state.phase != "active":
        raise GameRuleError(ErrorCode.WRONG_PHASE)
    if player.role != spec["role"]:
        raise GameRuleError(ErrorCode.WRONG_ROLE)
    if player.status == "eliminated":
        raise GameRuleError(ErrorCode.ELIMINATED)
    ready_at = player.cooldowns.get(power_id, 0)
    if s.state.game_elapsed_s < ready_at:
        raise GameRuleError(ErrorCode.COOLING_DOWN)
    if player.points < spec["cost"]:
        raise GameRuleError(ErrorCode.INSUFFICIENT_POINTS)
    _require_target(spec, kwargs)
    if power_id == "decoy":
        point = GeoPoint(lat=float(kwargs["lat"]), lon=float(kwargs["lon"]))
        if not contains(point, s.state.arena.boundary):
            raise GameRuleError(ErrorCode.TARGET_OUTSIDE)
        player.decoy_point = point
    elif power_id == "rescue":
        _rescue(s, kwargs)
    elif power_id == "create_safe":
        _create_safe(s, kwargs)
    elif power_id == "move_safe":
        _move_safe(s, kwargs)
    elif power_id == "shrink_now":
        _shrink_now(s)
    player.points -= spec["cost"]
    cooldown = int(spec["cooldown"] or 0)
    player.cooldowns[power_id] = s.state.game_elapsed_s + cooldown
    duration = spec["duration"]
    if power_id == "ghost":
        player.ghost_next_reveal = True
    elif power_id == "radar":
        _arm_timed(s, player_id, "radar", int(duration), on=player)
    elif power_id == "jammer":
        _arm_timed(s, player_id, "jammer", int(duration), on=s.state)
    elif power_id == "shield":
        _arm_timed(s, player_id, "shield", int(duration), on=player)
    elif power_id == "tracker":
        _arm_timed(s, player_id, "tracker", int(duration), on=player)
    elif power_id == "lockdown":
        _arm_timed(s, player_id, "lockdown", int(duration), on=s.state)
    elif power_id == "scan":
        _scan(s, player_id)
    s.emit("purchase", {"power": power_id, "text": f"{player.display_name} armed {power_id}."})
    s._note_input("purchase", {"player_id": str(player_id), "power_id": power_id, **kwargs})


def _arm_timed(
    s: GameSession,
    owner_id,
    effect: str,
    duration_s: int,
    *,
    on: Any,
) -> None:
    """Set `{effect}_until_s` on player or state, then register the timed effect."""
    setattr(on, f"{effect}_until_s", s.state.game_elapsed_s + duration_s)
    add_effect(s, owner_id=owner_id, type=effect, duration_s=duration_s)


def _require_target(spec: dict[str, Any], kwargs: dict[str, Any]) -> None:
    if not spec["needs_target"]:
        return
    kind = spec.get("target", "point")
    if kind == "player":
        if kwargs.get("target_player_id") is None:
            raise GameRuleError(ErrorCode.NEEDS_TARGET)
    elif kind == "zone_point":
        if kwargs.get("zone_id") is None or kwargs.get("lat") is None or kwargs.get("lon") is None:
            raise GameRuleError(ErrorCode.NEEDS_TARGET)
    elif kwargs.get("lat") is None or kwargs.get("lon") is None:
        raise GameRuleError(ErrorCode.NEEDS_TARGET)


def _rescuable(target) -> bool:
    """A converted seeker still hunting, or an eliminated hider.

    Convert tags leave a hider hunting as a seeker, so Rescue turns them back. Eliminate
    tags (Classic default and the PARK42 demo) leave no converted seeker, so Rescue brings
    an eliminated hider back into the hunt instead.
    TODO: confirm with Scott that Rescue should revive eliminated hiders. The catalog copy
    says "Bring a tagged player back", but the original spec only described convert-mode.
    """
    if target.role == "seeker":
        return target.converted_from_hider and target.status == "active"
    return target.role == "hider" and target.status == "eliminated"


def _rescue(s: GameSession, kwargs: dict[str, Any]) -> None:
    target_id = UUID(str(kwargs["target_player_id"]))
    target = s.state.players.get(target_id)
    if target is None or not _rescuable(target):
        raise GameRuleError(ErrorCode.TARGET_NOT_ACTIVE)
    settings = s.module_settings("power_ups")
    immunity_s = int(settings.get("rescue_duration", CATALOG["rescue"]["duration"]))
    target.role = "hider"
    target.status = "active"
    target.converted_from_hider = False
    # A revived hider must not carry the old out-of-bounds countdown into the next tick.
    target.bounds_phase = "inside"
    target.bounds_remaining_s = None
    target.oob_revealed = False
    target.shield_until_s = s.state.game_elapsed_s + immunity_s
    add_effect(s, owner_id=target_id, type="shield", duration_s=immunity_s)
    s.emit(
        "rescue",
        {"text": f"{target.display_name} was rescued.", "player_id": str(target_id)},
        player_id=target_id,
        tone="success",
    )


def _next_safe_name(zones: list[ArenaZone]) -> str:
    existing = sum(1 for z in zones if z.kind == ZoneKind.SAFE)
    return f"Safe {existing + 1}"


def _create_safe(s: GameSession, kwargs: dict[str, Any]) -> None:
    point = GeoPoint(lat=float(kwargs["lat"]), lon=float(kwargs["lon"]))
    if not contains(point, s.state.arena.boundary):
        raise GameRuleError(ErrorCode.TARGET_OUTSIDE)
    settings = s.module_settings("power_ups")
    radius_m = float(settings.get("create_safe_radius_m", 30))
    zone = ArenaZone(
        id=uuid4(),
        name=_next_safe_name(s.state.arena.zones),
        kind=ZoneKind.SAFE,
        shape=CircleShape(center=point, radius_m=radius_m),
    )
    arena = s.state.arena
    arena.zones = list(arena.zones) + [zone]
    s.state.arena = clip_arena(arena)
    kept = next((z for z in s.state.arena.zones if z.id == zone.id), None)
    if kept is None:
        raise GameRuleError(ErrorCode.TARGET_OUTSIDE, "Safe zone could not fit in the play area.")
    s.emit(
        "safe_created",
        {
            "text": "A new safe zone appeared.",
            "zone_id": str(zone.id),
            "lat": point.lat,
            "lon": point.lon,
            "radius_m": radius_m,
        },
        tone="info",
    )


def _move_safe(s: GameSession, kwargs: dict[str, Any]) -> None:
    zone_id = UUID(str(kwargs["zone_id"]))
    point = GeoPoint(lat=float(kwargs["lat"]), lon=float(kwargs["lon"]))
    if not contains(point, s.state.arena.boundary):
        raise GameRuleError(ErrorCode.TARGET_OUTSIDE)
    zone = next((z for z in s.state.arena.zones if z.id == zone_id), None)
    if zone is None or zone.kind != ZoneKind.SAFE:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Unknown safe zone.")
    if not isinstance(zone.shape, CircleShape):
        # TODO: translate polygon safe zones when the editor supports live reshape.
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Only circle safe zones can move.")
    radius_m = zone.shape.radius_m
    zone.shape = CircleShape(center=point, radius_m=radius_m)
    s.state.arena = clip_arena(s.state.arena)
    kept = next((z for z in s.state.arena.zones if z.id == zone_id), None)
    if kept is None:
        raise GameRuleError(ErrorCode.TARGET_OUTSIDE, "Safe zone could not fit in the play area.")
    s.emit(
        "safe_moved",
        {
            "text": f"{zone.name} moved.",
            "zone_id": str(zone_id),
            "lat": point.lat,
            "lon": point.lon,
            "radius_m": radius_m,
        },
        tone="info",
    )


def _shrink_now(s: GameSession) -> None:
    if not advance_shrink_schedule(s):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "No zone shrink is available.")
    apply_scheduled_shrink(s, emit_warning=False)


def _scan(s: GameSession, seeker_id) -> None:
    settings = s.module_settings("power_ups")
    radius_m = float(settings.get("scan_radius_m", 30))
    pin_count = max(1, int(settings.get("scan_count", 1)))
    hiders = [
        p
        for p in s.state.players.values()
        if p.role == "hider" and p.status == "active" and (p.last_precise or p.location)
    ]
    if not hiders:
        return
    picks = s.rng.sample(hiders, min(pin_count, len(hiders)))
    for target in picks:
        reading = target.last_precise or target.location
        assert reading is not None
        s.state.reveals.append(
            RevealPin(
                reveal_id=uuid4(),
                player_id=target.player_id,
                lat=reading.lat,
                lon=reading.lon,
                radius_m=radius_m,
                expires_at_game_s=s.state.game_elapsed_s + 10,
            )
        )
