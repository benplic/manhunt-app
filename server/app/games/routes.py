from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.games.service import GameService


class CreateGameIn(BaseModel):
    arena_id: UUID
    preset_id: str = "classic"
    overrides: dict[str, dict[str, Any]] = Field(default_factory=dict)


class JoinIn(BaseModel):
    join_code: str


class QrIn(BaseModel):
    token: str


def bind_game_routes(get_session, current_user, service: GameService):
    router = APIRouter(prefix="/v1", tags=["games"])

    @router.post("/games")
    async def create_game(
        body: CreateGameIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await service.create(session, user, body.arena_id, body.preset_id, body.overrides)
        return {"id": str(row.id), "join_code": row.join_code, "status": row.status}

    @router.post("/games/join")
    async def join_game(
        body: JoinIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await service.join(session, user, body.join_code)
        return {"id": str(row.id), "join_code": row.join_code, "status": row.status}

    @router.get("/games/{game_id}")
    async def get_game(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return await service.view(session, user, game_id)

    @router.post("/games/{game_id}/roles")
    async def roles(
        game_id: UUID,
        body: dict[str, Any],
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        game = await service.set_roles(session, user, game_id, body)
        from app.engine.views import build_view

        return build_view(game, user.id)

    @router.post("/games/{game_id}/start")
    async def start(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        from app.engine.views import build_view

        game = await service.start(session, user, game_id)
        return build_view(game, user.id)

    @router.post("/games/{game_id}/pause")
    async def pause(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        from app.engine.views import build_view

        return build_view(await service.pause(session, user, game_id), user.id)

    @router.post("/games/{game_id}/resume")
    async def resume(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        from app.engine.views import build_view

        return build_view(await service.resume(session, user, game_id), user.id)

    @router.post("/games/{game_id}/end")
    async def end(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        from app.engine.views import build_view

        return build_view(await service.end(session, user, game_id), user.id)

    @router.post("/games/{game_id}/leave")
    async def leave(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row, member = await service.require_member(session, game_id, user)
        await session.delete(member)
        await session.commit()
        return {"ok": True, "game_id": str(row.id)}

    @router.post("/games/{game_id}/tags/qr")
    async def qr_tag(
        game_id: UUID,
        body: QrIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        await service.qr_tag(session, user, game_id, body.token)
        return {"result": "accepted"}

    return router
