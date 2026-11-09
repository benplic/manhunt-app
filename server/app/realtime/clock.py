from datetime import UTC, datetime

from app.engine.clock import Clock


class WallClock(Clock):
    def now(self) -> datetime:
        return datetime.now(UTC)
