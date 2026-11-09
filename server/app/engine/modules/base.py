from __future__ import annotations

from typing import TYPE_CHECKING, Any, ClassVar

from app.errors import ErrorCode

if TYPE_CHECKING:
    from app.engine.events import GameEvent
    from app.engine.session import GameSession
    from app.engine.state import LocationReading, PlayerState, WinResult


class TagClaim:
    def __init__(
        self,
        seeker_id: Any,
        hider_id: Any,
        *,
        seeker_range: float | None = None,
        hider_range: float | None = None,
        qr_token: str | None = None,
    ) -> None:
        self.seeker_id = seeker_id
        self.hider_id = hider_id
        self.seeker_range = seeker_range
        self.hider_range = hider_range
        self.qr_token = qr_token


class BaseModule:
    module_id: ClassVar[str] = ""

    def __init__(self, settings: dict[str, Any]) -> None:
        self.settings = settings

    def on_start(self, s: GameSession) -> None:
        return None

    def on_tick(self, s: GameSession) -> None:
        return None

    def on_location(self, s: GameSession, p: PlayerState, r: LocationReading) -> None:
        return None

    def check_tag(self, s: GameSession, claim: TagClaim) -> ErrorCode | None:
        return None

    def on_event(self, s: GameSession, e: GameEvent) -> None:
        return None

    def check_win(self, s: GameSession) -> WinResult | None:
        return None
