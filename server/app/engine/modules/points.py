"""Awards close-call, survival, taunt, others-tagged, and tag bonuses."""

from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.geo import ACCURACY_CUTOFF_M, distance_m
from app.engine.modules.base import BaseModule
from app.engine.modules.effects import add_effect
from app.errors import ErrorCode, GameRuleError

if TYPE_CHECKING:
    from app.engine.session import GameSession


def grant_points(player, amount: int) -> None:
    gained = int(amount)
    if gained <= 0:
        return
    player.points += gained
    player.points_earned += gained


class PointsModule(BaseModule):
    module_id: ClassVar[str] = "points"

    def on_tick(self, s: GameSession) -> None:
        if s.state.phase != "active":
            return
        survival_every = int(self.settings.get("survival_s", 300))
        close_m = float(self.settings.get("close_m", 15))
        escape_m = float(self.settings.get("escape_m", 30))
        close_hold_s = int(self.settings.get("close_hold_s", 5))
        hiders = [p for p in s.state.players.values() if p.role == "hider" and p.status == "active"]
        seekers = [
            p for p in s.state.players.values() if p.role == "seeker" and p.status == "active"
        ]
        for hider in hiders:
            if s.state.game_elapsed_s - hider.last_survival_award_s >= survival_every:
                grant_points(hider, int(self.settings.get("survival_points", 10)))
                hider.last_survival_award_s = s.state.game_elapsed_s
            nearest = _nearest_seeker_m(hider, seekers)
            if nearest is None:
                continue
            if nearest <= close_m:
                if hider.close_near_since_s is None:
                    hider.close_near_since_s = s.state.game_elapsed_s
            elif nearest >= escape_m and hider.close_near_since_s is not None:
                held = s.state.game_elapsed_s - hider.close_near_since_s
                if held >= close_hold_s:
                    grant_points(hider, int(self.settings.get("close_call_points", 20)))
                    s.emit(
                        "close_call",
                        {"text": f"{hider.display_name} slipped a close call."},
                        player_id=hider.player_id,
                        tone="success",
                    )
                hider.close_near_since_s = None
            elif nearest > close_m:
                # Still not far enough to cash in; keep the clock running.
                pass

    def on_event(self, s: GameSession, e) -> None:
        if e.type != "tag":
            return
        bonus = int(self.settings.get("others_tagged_points", 15))
        remaining = [
            p for p in s.state.players.values() if p.role == "hider" and p.status == "active"
        ]
        for hider in remaining:
            grant_points(hider, bonus)


def apply_taunt(s: GameSession, player_id) -> None:
    if not bool(s.module_settings("points").get("taunt_enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Taunts are off.")
    player = s.state.players[player_id]
    if player.role != "hider" or player.status != "active":
        raise GameRuleError(ErrorCode.WRONG_ROLE)
    if s.state.phase != "active":
        raise GameRuleError(ErrorCode.WRONG_PHASE)
    now = s.state.game_elapsed_s
    ready = player.taunt_cooldown_until_s
    if ready is not None and now < ready:
        raise GameRuleError(ErrorCode.COOLING_DOWN, "Taunt is still cooling down.")
    seekers = [p for p in s.state.players.values() if p.role == "seeker"]
    dist = _nearest_seeker_m(player, seekers) or 200
    # Closer taunts score more. A distant ping is cheap bragging.
    points = max(5, int(40 - dist / 10))
    grant_points(player, points)
    duration = int(s.module_settings("points").get("taunt_s", 8))
    cooldown = int(s.module_settings("points").get("taunt_cooldown", 45))
    player.taunt_until_s = now + duration
    player.taunt_cooldown_until_s = now + max(0, cooldown)
    add_effect(s, owner_id=player_id, type="taunt", duration_s=duration)
    s.emit(
        "taunt",
        {"text": f"{player.display_name} taunted from {int(dist)} m.", "points": points},
        player_id=player_id,
        tone="info",
    )
    s._note_input("taunt", {"player_id": str(player_id)})


def _nearest_seeker_m(hider, seekers) -> float | None:
    if hider.location is None or hider.location.accuracy_m > ACCURACY_CUTOFF_M:
        return None
    best = None
    for seeker in seekers:
        if seeker.location is None or seeker.location.accuracy_m > ACCURACY_CUTOFF_M:
            continue
        dist = distance_m(hider.location.point, seeker.location.point)
        best = dist if best is None else min(best, dist)
    return best
