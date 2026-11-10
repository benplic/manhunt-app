"""Per-user join attempt cap. Stops a player from guessing 6-character codes."""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from collections.abc import Callable
from uuid import UUID

from app.errors import ApiError, ErrorCode

log = logging.getLogger(__name__)

# Ten tries, then the eleventh inside the same minute is refused. Rejected
# tries are recorded too, so a tight retry loop does not reset the window.
JOIN_LIMIT = 10
JOIN_WINDOW_S = 60.0


class JoinRateLimiter:
    """In-memory sliding window. One process, one event loop, so no lock."""

    def __init__(
        self,
        *,
        limit: int = JOIN_LIMIT,
        window_s: float = JOIN_WINDOW_S,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.limit = limit
        self.window_s = window_s
        self.clock = clock
        self._hits: dict[UUID, list[float]] = defaultdict(list)

    def hit(self, user_id: UUID) -> None:
        now = self.clock()
        recent = [stamp for stamp in self._hits[user_id] if now - stamp < self.window_s]
        recent.append(now)
        self._hits[user_id] = recent
        if len(recent) > self.limit:
            log.warning("join_rate_limited user_id=%s", user_id)
            raise ApiError(
                ErrorCode.RATE_LIMITED,
                "Too many join attempts. Wait a minute and try again.",
                status_code=429,
            )
