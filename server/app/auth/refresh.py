"""Hashed rotating refresh tokens. Access JWTs stay 24 hours."""

from __future__ import annotations

import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.tokens import issue_token
from app.db.models import RefreshToken
from app.errors import ApiError, ErrorCode


def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def mint_refresh() -> str:
    return secrets.token_urlsafe(32)


async def store_refresh(session: AsyncSession, user_id: UUID, raw: str, days: int = 30) -> None:
    session.add(
        RefreshToken(
            id=uuid4(),
            user_id=user_id,
            token_hash=hash_token(raw),
            expires_at=datetime.now(UTC) + timedelta(days=days),
        )
    )


async def rotate_refresh(
    session: AsyncSession, raw: str, signing_key: str
) -> tuple[str, str, datetime]:
    digest = hash_token(raw)
    row = await session.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == digest,
            RefreshToken.revoked.is_(False),
        )
    )
    if row is None:
        raise ApiError(ErrorCode.TOKEN_INVALID, "Refresh token is not valid.", status_code=401)
    expires = row.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=UTC)
    if expires < datetime.now(UTC):
        raise ApiError(ErrorCode.TOKEN_INVALID, "Refresh token is not valid.", status_code=401)
    row.revoked = True
    access, expires = issue_token(row.user_id, signing_key)
    new_raw = mint_refresh()
    await store_refresh(session, row.user_id, new_raw)
    await session.commit()
    return access, new_raw, expires
