"""In-memory state for PARK42 demo sessions."""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Literal
from uuid import UUID

from app.engine.geo import GeoPoint

if TYPE_CHECKING:
    from app.engine.session import GameSession

DemoBotMode = Literal["auto", "go_dark", "oob"]
ALLOWED_SPEEDS = (1, 2, 5, 10)


@dataclass
class DemoState:
    rng: random.Random
    bot_ids: list[UUID] = field(default_factory=list)
    speed: int = 1
    lobby_hold: bool = False
    bot_modes: dict[UUID, DemoBotMode] = field(default_factory=dict)
    bot_headings: dict[UUID, float] = field(default_factory=dict)
    human_targets: dict[UUID, GeoPoint] = field(default_factory=dict)
    last_bot_tag_s: int | None = None
    head_start_ended_at_s: int | None = None
    bot_backoff_until_s: dict[UUID, int] = field(default_factory=dict)
    walk_speed_mps: float = 5.0

    @classmethod
    def initial(cls, session: GameSession, *, bot_ids: list[UUID]) -> DemoState:
        rng = random.Random(session.state.seed ^ 0x5EED)
        modes: dict[UUID, DemoBotMode] = {bot_id: "auto" for bot_id in bot_ids}
        headings: dict[UUID, float] = {
            bot_id: rng.random() * 6.283185307179586 for bot_id in bot_ids
        }
        return cls(
            rng=rng,
            bot_ids=list(bot_ids),
            bot_modes=modes,
            bot_headings=headings,
        )

    def is_bot(self, player_id: UUID) -> bool:
        return player_id in self.bot_modes
