from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt

from app.errors import ApiError, ErrorCode


def issue_token(user_id: UUID, key: str, hours: int = 24) -> tuple[str, datetime]:
    expires = datetime.now(UTC) + timedelta(hours=hours)
    token = jwt.encode(
        {"sub": str(user_id), "exp": expires},
        key,
        algorithm="HS256",
    )
    return token, expires


def parse_token(token: str, key: str) -> UUID:
    try:
        payload = jwt.decode(token, key, algorithms=["HS256"])
        return UUID(str(payload["sub"]))
    except jwt.ExpiredSignatureError as exc:
        raise ApiError(ErrorCode.TOKEN_EXPIRED, "Session expired.", status_code=401) from exc
    except (jwt.InvalidTokenError, ValueError, KeyError) as exc:
        raise ApiError(ErrorCode.TOKEN_INVALID, "Invalid session.", status_code=401) from exc
