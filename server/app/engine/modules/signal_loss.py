from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.modules.base import BaseModule
from app.engine.state import Banner

if TYPE_CHECKING:
    from app.engine.session import GameSession


class SignalLossModule(BaseModule):
    module_id: ClassVar[str] = "signal_loss"

    def on_tick(self, s: GameSession) -> None:
        if not bool(self.settings.get("enabled", True)):
            return
        if s.state.phase in {"lobby", "ended"}:
            return
        silence = int(self.settings.get("silence", 45))
        now = s.clock.now()
        for player in s.state.players.values():
            if player.status == "eliminated":
                continue
            last = player.last_location_at
            if last is None:
                last = now
                player.last_location_at = now
            elapsed = (now - last).total_seconds()
            if elapsed >= silence and player.status != "signal_lost":
                player.status = "signal_lost"
                s.state.safety_needs_ack = True
                s.state.banners.append(
                    Banner(
                        banner_id=uuid4(),
                        tone="safety",
                        title=f"{player.display_name} went dark",
                        detail=(
                            "Last precise fix is on the map for everyone. "
                            "Safety overrides the hunt."
                        ),
                        player_id=player.player_id,
                    )
                )
                s.emit(
                    "signal_lost",
                    {"text": f"{player.display_name} went dark."},
                    player_id=player.player_id,
                    tone="safety",
                )
            elif elapsed < silence and player.status == "signal_lost":
                player.status = "active"
                s.state.banners = [
                    b
                    for b in s.state.banners
                    if b.player_id != player.player_id or b.tone != "safety"
                ]
            penalty_after = int(self.settings.get("penalty_after", 180))
            penalty = str(self.settings.get("penalty", "none"))
            if (
                player.status == "signal_lost"
                and penalty == "eliminate"
                and elapsed >= penalty_after
                and player.role == "hider"
            ):
                player.status = "eliminated"
                s.emit(
                    "signal_loss_penalty",
                    {"text": f"{player.display_name} was eliminated after going dark."},
                    player_id=player.player_id,
                    tone="warning",
                )
