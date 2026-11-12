from __future__ import annotations

from typing import TYPE_CHECKING, Any, ClassVar

from app.engine.arena import PLAY_CIRCLE_STEPS, CircleShape, clip_arena
from app.engine.geo import circle_sample_ring
from app.engine.modules.base import BaseModule

if TYPE_CHECKING:
    from app.engine.session import GameSession


class ZoneShrinkModule(BaseModule):
    module_id: ClassVar[str] = "zone_shrink"

    def on_start(self, s: GameSession) -> None:
        self._maybe_warn(s)

    def on_tick(self, s: GameSession) -> None:
        if not bool(self.settings.get("enabled", False)):
            return
        circle = s.state.arena.boundary_circle
        if circle is None:
            return
        schedule = zone_shrink_schedule(s)
        if schedule is None:
            return
        target_r = schedule["target_radius_m"]
        if target_r < circle.radius_m:
            s.state.arena.boundary_circle = CircleShape(center=circle.center, radius_m=target_r)
            s.state.arena.boundary = circle_sample_ring(
                circle.center, target_r, steps=PLAY_CIRCLE_STEPS
            )
            s.state.arena = clip_arena(s.state.arena)
            s.emit(
                "zone_shrunk",
                {"text": f"Zone shrunk to {int(round(target_r))} m."},
                tone="warning",
            )
        self._maybe_warn(s)

    def _maybe_warn(self, s: GameSession) -> None:
        schedule = zone_shrink_schedule(s)
        if schedule is None:
            return
        shrinks_in_s = schedule["shrinks_in_s"]
        next_r = schedule["next_radius_m"]
        if shrinks_in_s is None or next_r is None:
            return
        if 0 < shrinks_in_s <= 60:
            upcoming_step = schedule["step"] + 1
            if s.state.last_zone_warned_step < upcoming_step:
                s.state.last_zone_warned_step = upcoming_step
                s.emit(
                    "zone_warning",
                    {"text": f"Zone shrinks to {int(round(next_r))} m in 1 min."},
                    tone="warning",
                )


def zone_shrink_schedule(s: GameSession) -> dict[str, Any] | None:
    """Compute shrink radius and countdown purely from game_elapsed_s."""
    state = s.state
    circle = state.arena.boundary_circle
    settings = s.module_settings("zone_shrink")
    if circle is None or not bool(settings.get("enabled", False)):
        return None
    initial_r = state.initial_radius_m or circle.radius_m
    every_s = max(60, int(settings.get("every", 5)) * 60)
    ratio = float(settings.get("shrink_to", 75)) / 100.0
    min_r = float(settings.get("min_radius_m", 50))
    hs = s.module_settings("head_start")
    head_start_s = int(hs.get("duration", 60)) if bool(hs.get("enabled", True)) else 0

    if state.game_elapsed_s <= head_start_s:
        steps = 0
    else:
        steps = (state.game_elapsed_s - head_start_s) // every_s

    if steps == 0 or initial_r <= min_r:
        target_r = initial_r
    else:
        target_r = max(min_r, round(initial_r * (ratio**steps), 2))

    next_step_at_s = head_start_s + (steps + 1) * every_s
    next_candidate = max(min_r, round(initial_r * (ratio ** (steps + 1)), 2))
    can_shrink_more = (
        state.phase != "ended"
        and target_r > min_r
        and next_candidate < circle.radius_m
        and next_candidate < target_r
    )
    next_radius_m = next_candidate if can_shrink_more else None
    if not can_shrink_more:
        shrinks_in_s = None
    elif state.phase == "lobby":
        shrinks_in_s = every_s
    else:
        shrinks_in_s = max(0, next_step_at_s - state.game_elapsed_s)

    return {
        "step": steps,
        "target_radius_m": target_r,
        "current_radius_m": circle.radius_m,
        "next_radius_m": next_radius_m,
        "shrinks_in_s": shrinks_in_s,
    }
