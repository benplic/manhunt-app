"""Sign in with Apple. Verifies the identity token against Apple's JWKS."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

import jwt
from jwt import PyJWKClient

from app.errors import ApiError, ErrorCode

APPLE_ISS = "https://appleid.apple.com"
APPLE_JWKS = "https://appleid.apple.com/auth/keys"

# Tests replace this with a stub that returns a matching JWK set.
JWKSClientFactory: Callable[[str], Any] = PyJWKClient


async def verify_apple_token(identity_token: str, audience: str) -> str:
    if not identity_token:
        raise ApiError(ErrorCode.TOKEN_INVALID, "Missing identity token.", status_code=401)
    try:
        client = JWKSClientFactory(APPLE_JWKS)
        signing = client.get_signing_key_from_jwt(identity_token)
        payload = jwt.decode(
            identity_token,
            signing.key,
            algorithms=["RS256"],
            audience=audience,
            issuer=APPLE_ISS,
        )
    except jwt.ExpiredSignatureError as exc:
        raise ApiError(ErrorCode.TOKEN_EXPIRED, "Apple token expired.", status_code=401) from exc
    except jwt.InvalidTokenError as exc:
        raise ApiError(
            ErrorCode.TOKEN_INVALID, "Apple token was rejected.", status_code=401
        ) from exc
    except Exception as exc:
        raise ApiError(
            ErrorCode.TOKEN_INVALID, "Apple token was rejected.", status_code=401
        ) from exc
    sub = payload.get("sub")
    if not sub:
        raise ApiError(ErrorCode.TOKEN_INVALID, "Apple token missing sub.", status_code=401)
    return str(sub)


_ = Awaitable
