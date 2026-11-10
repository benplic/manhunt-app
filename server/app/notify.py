"""APNs delivery. Tests assert in-memory records; a .p8 in Key Vault enables send."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt

from app.config import Settings, get_settings

log = logging.getLogger("manhunt.notify")


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
        record = Notification(user_id, title, body, payload or {})
        self.sent.append(record)
        settings = get_settings()
        have_key = settings.manhunt_apns_key and settings.manhunt_apns_key_id
        if not (have_key and settings.manhunt_apns_team_id):
            return
        token = (payload or {}).get("device_token")
        if not token:
            return
        try:
            _send_apns(settings, str(token), title, body, record.payload)
        except Exception:
            # TODO: retry failed APNs pushes; do not include the p8 or device token.
            log.exception("apns_send_failed user_id=%s", user_id)


def _send_apns(settings: Settings, device_token: str, title: str, body: str, payload: dict) -> None:
    now = datetime.now(UTC)
    token = jwt.encode(
        {
            "iss": settings.manhunt_apns_team_id,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(minutes=50)).timestamp()),
        },
        settings.manhunt_apns_key,
        algorithm="ES256",
        headers={"kid": settings.manhunt_apns_key_id},
    )
    host = (
        "api.push.apple.com" if settings.manhunt_apns_production else "api.sandbox.push.apple.com"
    )
    import httpx

    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": settings.manhunt_apns_bundle_id,
        "apns-push-type": "alert",
    }
    url = f"https://{host}/3/device/{device_token}"
    alert = {"title": title, "body": body}
    body_json = {"aps": {"alert": alert}, "game_id": payload.get("game_id")}
    # HTTP/2 is required by APNs. httpx uses h2 when installed.
    with httpx.Client(http2=True, timeout=10) as client:
        response = client.post(url, headers=headers, json=body_json)
        if response.status_code >= 300:
            log.warning("apns_rejected status=%s", response.status_code)


notifier = Notifier()
