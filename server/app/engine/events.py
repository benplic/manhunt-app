"""In-memory event records. Persistence happens outside the engine."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from uuid import UUID


@dataclass
class GameEvent:
    seq: int
    type: str
    payload: dict[str, Any]
    tone: str = "info"
    player_id: UUID | None = None
    sensitive: bool = False
    created_at: datetime | None = None
    text: str = ""
    extra: dict[str, Any] = field(default_factory=dict)
    # The event announces something the actor did ("sent a last fix"). Everyone else
    # gets it. The actor, `player_id`, already knows and must not see it as an alert.
    hide_from_actor: bool = False


def visible_to(event: GameEvent, player_id: UUID) -> bool:
    """Whether a player's event stream may include this event.

    Decided on ids, never on text, so live push, reconnect replay, and the persisted
    timeline all agree.
    """
    if event.sensitive:
        return False
    return not (event.hide_from_actor and event.player_id == player_id)
