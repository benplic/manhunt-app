"""Server-side purchase pipeline. Mirrors iOS PowerUpRules."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, ClassVar
from uuid import uuid4

from app.engine.geo import GeoPoint, contains
from app.engine.modules.base import BaseModule, TagClaim
from app.engine.modules.effects import add_effect, has_effect
from app.engine.state import RevealPin
from app.errors import ErrorCode, GameRuleError

if TYPE_CHECKING:
    from app.engine.session import GameSession

CATALOG: dict[str, dict[str, Any]] = {
    "ghost": {"role": "hider", "cost": 20, "duration": None, "cooldown": 20, "needs_target": False},
    "decoy": {"role": "hider", "cost": 40, "duration": None, "cooldown": 30, "needs_target": True},
    "radar": {"role": "hider", "cost": 40, "duration": 20, "cooldown": 40, "needs_target": False},
    "jammer": {"role": "hider", "cost": 55, "duration": 60, "cooldown": 90, "needs_target": False},
    "shield": {"role": "hider", "cost": 70, "duration": 30, "cooldown": 60, "needs_target": False},
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
}


def resolve_power(s: GameSession, power_id: str) -> dict[str, Any]:
    base = CATALOG.get(power_id)
    if base is None:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, f"Unknown power-up {power_id}.")
    settings = s.module_settings("power_ups")
    if not bool(settings.get("enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Power-ups are off.")
    if not bool(settings.get(f"{power_id}_enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "That power-up is off.")
    spec = dict(base)
    spec["cost"] = int(settings.get(f"{power_id}_cost", base["cost"]))
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
    if spec["needs_target"] and kwargs.get("lat") is None:
        raise GameRuleError(ErrorCode.NEEDS_TARGET)
    if power_id == "decoy":
        point = GeoPoint(lat=float(kwargs["lat"]), lon=float(kwargs["lon"]))
        if not contains(point, s.state.arena.boundary):
            raise GameRuleError(ErrorCode.TARGET_OUTSIDE)
        player.decoy_point = point
    player.points -= spec["cost"]
    cooldown = int(spec["cooldown"] or 0)
    player.cooldowns[power_id] = s.state.game_elapsed_s + cooldown
    duration = spec["duration"]
    if power_id == "ghost":
        player.ghost_next_reveal = True
    elif power_id == "radar":
        player.radar_until_s = s.state.game_elapsed_s + int(duration)
        add_effect(s, owner_id=player_id, type="radar", duration_s=int(duration))
    elif power_id == "jammer":
        s.state.jammer_until_s = s.state.game_elapsed_s + int(duration)
        add_effect(s, owner_id=player_id, type="jammer", duration_s=int(duration))
    elif power_id == "shield":
        player.shield_until_s = s.state.game_elapsed_s + int(duration)
        add_effect(s, owner_id=player_id, type="shield", duration_s=int(duration))
    elif power_id == "tracker":
        player.tracker_until_s = s.state.game_elapsed_s + int(duration)
        add_effect(s, owner_id=player_id, type="tracker", duration_s=int(duration))
    elif power_id == "lockdown":
        s.state.lockdown_until_s = s.state.game_elapsed_s + int(duration)
        add_effect(s, owner_id=player_id, type="lockdown", duration_s=int(duration))
    elif power_id == "scan":
        _scan(s, player_id)
    s.emit("purchase", {"power": power_id, "text": f"{player.display_name} armed {power_id}."})
    s._note_input("purchase", {"player_id": str(player_id), "power_id": power_id, **kwargs})


def _scan(s: GameSession, seeker_id) -> None:
    hiders = [
        p
        for p in s.state.players.values()
        if p.role == "hider" and p.status == "active" and (p.last_precise or p.location)
    ]
    if not hiders:
        return
    target = hiders[s.rng.randrange(len(hiders))]
    reading = target.last_precise or target.location
    assert reading is not None
    fuzz = float(s.module_settings("reveal_fuzzy").get("fuzz", 30))
    s.state.reveals.append(
        RevealPin(
            reveal_id=uuid4(),
            player_id=target.player_id,
            lat=reading.lat,
            lon=reading.lon,
            radius_m=fuzz,
            expires_at_game_s=s.state.game_elapsed_s + 10,
        )
    )
