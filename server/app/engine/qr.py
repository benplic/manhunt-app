"""Rotating HMAC-SHA256 QR tokens. Key comes from settings, never the repo."""

from __future__ import annotations

import hashlib
import hmac
import json
from base64 import urlsafe_b64decode, urlsafe_b64encode
from datetime import datetime, timedelta
from uuid import UUID

from app.errors import ErrorCode, GameRuleError


def _b64(data: bytes) -> str:
    return urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _unb64(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return urlsafe_b64decode(text + padding)


def make_qr_token(*, game_id: UUID, hider_id: UUID, expires_at: datetime, key: str) -> str:
    payload = {
        "g": str(game_id),
        "h": str(hider_id),
        "exp": int(expires_at.timestamp()),
    }
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    sig = hmac.new(key.encode("utf-8"), raw, hashlib.sha256).digest()
    return f"{_b64(raw)}.{_b64(sig)}"


def parse_qr_token(token: str, *, game_id: UUID, key: str, now: datetime) -> UUID:
    try:
        body, sig = token.split(".", 1)
        raw = _unb64(body)
        expected = hmac.new(key.encode("utf-8"), raw, hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _unb64(sig)):
            raise GameRuleError(ErrorCode.TOKEN_INVALID, "QR signature does not match.")
        payload = json.loads(raw.decode("utf-8"))
        if payload.get("g") != str(game_id):
            raise GameRuleError(ErrorCode.TOKEN_INVALID, "QR token is for a different game.")
        exp = datetime.fromtimestamp(int(payload["exp"]), tz=now.tzinfo)
        if now >= exp:
            raise GameRuleError(ErrorCode.TOKEN_EXPIRED, "QR token has expired.")
        return UUID(str(payload["h"]))
    except (ValueError, KeyError, json.JSONDecodeError) as exc:
        raise GameRuleError(ErrorCode.TOKEN_INVALID, "QR token is malformed.") from exc


def token_ttl() -> timedelta:
    return timedelta(seconds=30)
