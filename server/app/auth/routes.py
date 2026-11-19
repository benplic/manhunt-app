import hmac

from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.apple import verify_apple_token
from app.auth.names import assert_display_name_allowed, normalize_display_name
from app.auth.refresh import mint_refresh, rotate_refresh, store_refresh
from app.auth.tokens import issue_token
from app.db.models import DeviceToken, User
from app.errors import ApiError, ErrorCode


class DevAuthIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=40)
    # Stable per-install id so two phones can share a display name before Apple auth.
    installation_id: str = Field(min_length=8, max_length=80)
    age: int = Field(ge=0, le=120)


class AppleAuthIn(BaseModel):
    identity_token: str
    display_name: str | None = None


class RefreshIn(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    id: str
    display_name: str
    avatar_url: str | None = None


class AuthOut(BaseModel):
    access_token: str
    expires_at: str
    user: UserOut
    refresh_token: str | None = None


def _install_handle(installation_id: str) -> str:
    cleaned = "".join(ch.lower() if ch.isalnum() else "-" for ch in installation_id).strip("-")
    return f"install-{(cleaned or 'device')[:64]}"


def _user_out(user: User) -> UserOut:
    # avatar_url is wired for clients; upload is intentionally not implemented yet.
    return UserOut(id=str(user.id), display_name=user.display_name, avatar_url=None)


async def _issue(session: AsyncSession, user: User, settings) -> AuthOut:
    token, expires = issue_token(user.id, settings.manhunt_session_signing_key)
    refresh = mint_refresh()
    await store_refresh(session, user.id, refresh)
    await session.commit()
    return AuthOut(
        access_token=token,
        expires_at=expires.isoformat(),
        user=_user_out(user),
        refresh_token=refresh,
    )


def _dev_secret_ok(presented: str, expected: str) -> bool:
    if not expected or len(presented) != len(expected):
        return False
    return hmac.compare_digest(presented, expected)


def bind_auth_routes(get_session, get_settings, current_user):
    from app.games.join_limit import DevAuthRateLimiter

    dev_limiter = DevAuthRateLimiter()
    router = APIRouter(prefix="/v1/auth", tags=["auth"])

    @router.post("/dev", response_model=AuthOut)
    async def dev_auth(
        body: DevAuthIn,
        request: Request,
        session: AsyncSession = Depends(get_session),
        dev_secret: str | None = Header(default=None, alias="X-Manhunt-Dev-Secret"),
    ) -> AuthOut:
        settings = get_settings()
        if not settings.manhunt_dev_auth:
            raise ApiError(ErrorCode.FORBIDDEN, "Dev sign-in is disabled.", status_code=403)
        client_ip = request.client.host if request.client else "unknown"
        dev_limiter.hit(client_ip)
        # Home publishes this route through the tunnel. The party secret is
        # what stops a stranger who only has the URL from minting accounts.
        if settings.manhunt_env == "home" or settings.manhunt_dev_auth_secret:
            if not _dev_secret_ok(dev_secret or "", settings.manhunt_dev_auth_secret):
                raise ApiError(ErrorCode.FORBIDDEN, "Dev sign-in is disabled.", status_code=403)
        if body.age < 13:
            raise ApiError(
                ErrorCode.TOO_YOUNG,
                "Manhunt is not available for people under 13.",
                status_code=403,
            )
        assert_display_name_allowed(body.display_name)
        name = normalize_display_name(body.display_name)
        handle = _install_handle(body.installation_id)
        user = await session.scalar(select(User).where(User.dev_handle == handle))
        if user is None:
            user = User(dev_handle=handle, display_name=name)
            session.add(user)
            await session.commit()
            await session.refresh(user)
        elif user.display_name != name:
            # Same install can rename between Play taps; identity stays the install id.
            user.display_name = name
            await session.commit()
            await session.refresh(user)
        return await _issue(session, user, settings)

    @router.post("/apple", response_model=AuthOut)
    async def apple_auth(
        body: AppleAuthIn, session: AsyncSession = Depends(get_session)
    ) -> AuthOut:
        settings = get_settings()
        sub = await verify_apple_token(body.identity_token, settings.manhunt_apple_audience)
        user = await session.scalar(select(User).where(User.apple_sub == sub))
        if user is None:
            name = (body.display_name or "Player").strip() or "Player"
            user = User(apple_sub=sub, display_name=name)
            session.add(user)
            await session.commit()
            await session.refresh(user)
        return await _issue(session, user, settings)

    @router.post("/refresh", response_model=AuthOut)
    async def refresh(body: RefreshIn, session: AsyncSession = Depends(get_session)) -> AuthOut:
        settings = get_settings()
        access, new_refresh, expires = await rotate_refresh(
            session, body.refresh_token, settings.manhunt_session_signing_key
        )
        # rotate_refresh already committed; load the user from the new access token.
        from app.auth.tokens import parse_token

        user_id = parse_token(access, settings.manhunt_session_signing_key)
        user = await session.get(User, user_id)
        if user is None:
            raise ApiError(ErrorCode.UNAUTHORIZED, "Unknown user.", status_code=401)
        return AuthOut(
            access_token=access,
            expires_at=expires.isoformat(),
            user=_user_out(user),
            refresh_token=new_refresh,
        )

    return router


class DeviceTokenIn(BaseModel):
    token: str = Field(min_length=8, max_length=256)


def bind_me_routes(get_session, current_user):
    me_router = APIRouter(prefix="/v1", tags=["auth"])

    @me_router.get("/me")
    async def me(user=Depends(current_user)) -> dict:
        return {"id": str(user.id), "display_name": user.display_name, "avatar_url": None}

    @me_router.put("/me/device-token")
    async def save_device_token(
        body: DeviceTokenIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await session.get(DeviceToken, user.id)
        if row is None:
            session.add(DeviceToken(user_id=user.id, token=body.token))
        else:
            row.token = body.token
        await session.commit()
        return {"ok": True}

    return me_router
