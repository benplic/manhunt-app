from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.modules.base import BaseModule
from app.engine.state import WinResult

if TYPE_CHECKING:
    from app.engine.session import GameSession


class WinModule(BaseModule):
    module_id: ClassVar[str] = "win"

    def on_start(self, s: GameSession) -> None:
        limit_min = int(self.settings.get("time_limit", 30))
        s.state.time_limit_remaining_s = limit_min * 60

    def on_tick(self, s: GameSession) -> None:
        if s.state.time_limit_remaining_s is None:
            return
        if s.state.phase in {"active", "head_start"}:
            s.state.time_limit_remaining_s = max(0, s.state.time_limit_remaining_s - 1)

    def check_win(self, s: GameSession) -> WinResult | None:
        if not bool(self.settings.get("enabled", True)):
            return None
        if s.state.phase in {"lobby", "ended"}:
            return None
        condition = self.settings.get("condition", "either")
        hiders = [p for p in s.state.players.values() if p.role == "hider"]
        active_hiders = [p for p in hiders if p.status == "active"]
        all_caught = bool(hiders) and not active_hiders
        timed_out = (s.state.time_limit_remaining_s or 1) <= 0 and s.state.phase == "active"
        if all_caught and condition in {"all_caught", "either"}:
            return WinResult(winner="seekers", reason="All hiders were tagged.")
        if timed_out and condition in {"time_limit", "either"}:
            return WinResult(winner="hiders", reason="Time ran out.")
        return None
