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
