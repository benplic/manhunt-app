from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.apple import verify_apple_token
from app.auth.tokens import issue_token
from app.db.models import User
from app.errors import ApiError, ErrorCode


class DevAuthIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=40)


class AppleAuthIn(BaseModel):
    identity_token: str
    display_name: str | None = None


class UserOut(BaseModel):
    id: str
    display_name: str


class AuthOut(BaseModel):
    access_token: str
    expires_at: str
    user: UserOut


def _handle(name: str) -> str:
    return "".join(ch.lower() if ch.isalnum() else "-" for ch in name).strip("-")[:40] or "player"


def bind_auth_routes(get_session, get_settings, current_user):
    router = APIRouter(prefix="/v1/auth", tags=["auth"])

    @router.post("/dev", response_model=AuthOut)
    async def dev_auth(body: DevAuthIn, session: AsyncSession = Depends(get_session)) -> AuthOut:
        settings = get_settings()
        if not settings.manhunt_dev_auth:
            raise ApiError(ErrorCode.FORBIDDEN, "Dev sign-in is disabled.", status_code=403)
        handle = _handle(body.display_name)
        user = await session.scalar(select(User).where(User.dev_handle == handle))
        if user is None:
            user = User(dev_handle=handle, display_name=body.display_name.strip())
            session.add(user)
            await session.commit()
            await session.refresh(user)
        token, expires = issue_token(user.id, settings.manhunt_session_signing_key)
        return AuthOut(
            access_token=token,
            expires_at=expires.isoformat(),
            user=UserOut(id=str(user.id), display_name=user.display_name),
        )

    @router.post("/apple", response_model=AuthOut)
    async def apple_auth(body: AppleAuthIn) -> AuthOut:
        await verify_apple_token(body.identity_token, get_settings().manhunt_apple_audience)
        raise ApiError(ErrorCode.INTERNAL, "unreachable", status_code=501)

    return router


def bind_me_routes(get_session, current_user):
    me_router = APIRouter(prefix="/v1", tags=["auth"])

    @me_router.get("/me")
    async def me(user=Depends(current_user)) -> dict:
        return {"id": str(user.id), "display_name": user.display_name}

    return me_router
