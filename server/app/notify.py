"""APNs stub. Phase 2 records payloads so tests can assert without a cert."""

from __future__ import annotations

from dataclasses import dataclass, field
from uuid import UUID


@dataclass
class Notification:
    user_id: UUID
    title: str
    body: str
    payload: dict = field(default_factory=dict)


class Notifier:
    def __init__(self) -> None:
        self.sent: list[Notification] = []

    def notify(self, user_id: UUID, title: str, body: str, payload: dict | None = None) -> None:
        # TODO: send via APNs when the paid Apple team and .p8 key are in Key Vault.
        self.sent.append(Notification(user_id, title, body, payload or {}))


notifier = Notifier()
