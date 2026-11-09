from uuid import UUID

from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.tokens import parse_token
from app.db.models import User
from app.errors import ApiError, ErrorCode


async def current_user(
    authorization: str | None = Header(default=None),
    session: AsyncSession = None,  # filled by app.main
    settings=None,
) -> User:
    raise RuntimeError("current_user is bound in create_app")


def bind_current_user(get_session, get_settings):
    async def _current_user(
        authorization: str | None = Header(default=None),
        session: AsyncSession = Depends(get_session),
    ) -> User:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise ApiError(ErrorCode.UNAUTHORIZED, "Sign in required.", status_code=401)
        token = authorization.split(" ", 1)[1]
        user_id: UUID = parse_token(token, get_settings().manhunt_session_signing_key)
        user = await session.get(User, user_id)
        if user is None:
            raise ApiError(ErrorCode.UNAUTHORIZED, "Unknown user.", status_code=401)
        return user

    return _current_user


async def user_by_id(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.scalar(select(User).where(User.id == user_id))
