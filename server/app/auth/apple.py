"""Sign in with Apple. Stub until Phase 2."""

from app.errors import ApiError, ErrorCode


async def verify_apple_token(_identity_token: str, _audience: str) -> str:
    raise ApiError(
        ErrorCode.INTERNAL,
        "Sign in with Apple arrives in Phase 2. Use POST /v1/auth/dev on a home server.",
        status_code=501,
    )
