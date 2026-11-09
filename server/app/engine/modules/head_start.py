from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.modules.base import BaseModule

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
