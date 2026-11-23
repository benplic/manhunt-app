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


# A new dev-auth install is a new user id, so the per-user cap alone does not
# hold. The IP cap is the backstop. Sized for a full lobby (MAX_GAME_PLAYERS=30)
# joining from one park NAT, with a little room for retries after a bad code.
JOIN_IP_LIMIT = 80
DEV_AUTH_IP_LIMIT = 80


class JoinRateLimiter:
    """In-memory sliding window. One process, one event loop, so no lock."""

    def __init__(
        self,
        *,
        limit: int = JOIN_LIMIT,
        ip_limit: int = JOIN_IP_LIMIT,
        window_s: float = JOIN_WINDOW_S,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.limit = limit
        self.ip_limit = ip_limit
        self.window_s = window_s
        self.clock = clock
        self._hits: dict[UUID, list[float]] = defaultdict(list)
        self._ip_hits: dict[str, list[float]] = defaultdict(list)

    def hit(self, user_id: UUID, client_ip: str | None = None) -> None:
        self._charge(self._hits, user_id, self.limit, f"user_id={user_id}")
        if client_ip:
            self._charge(self._ip_hits, client_ip, self.ip_limit, f"ip={client_ip}")

    def _charge(self, store: dict, key, limit: int, label: str) -> None:
        now = self.clock()
        recent = [stamp for stamp in store[key] if now - stamp < self.window_s]
        recent.append(now)
        store[key] = recent
        if len(recent) > limit:
            log.warning("join_rate_limited %s", label)
            raise ApiError(
                ErrorCode.RATE_LIMITED,
                "Too many join attempts. Wait a minute and try again.",
                status_code=429,
            )


class DevAuthRateLimiter:
    """Caps POST /v1/auth/dev per client address."""

    def __init__(
        self,
        *,
        limit: int = DEV_AUTH_IP_LIMIT,
        window_s: float = JOIN_WINDOW_S,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.limit = limit
        self.window_s = window_s
        self.clock = clock
        self._hits: dict[str, list[float]] = defaultdict(list)

    def hit(self, client_ip: str) -> None:
        now = self.clock()
        recent = [stamp for stamp in self._hits[client_ip] if now - stamp < self.window_s]
        recent.append(now)
        self._hits[client_ip] = recent
        if len(recent) > self.limit:
            log.warning("dev_auth_rate_limited ip=%s", client_ip)
            raise ApiError(
                ErrorCode.RATE_LIMITED,
                "Too many sign-in attempts. Wait a minute and try again.",
                status_code=429,
            )
