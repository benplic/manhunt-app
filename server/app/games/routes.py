from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, Request
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


class LobbyCircleIn(BaseModel):
    radius_m: float = Field(ge=30, le=2000)
    center: dict[str, float] | None = None


def _view(service: GameService, game, user_id: UUID) -> dict:
    from app.engine.views import build_view

    return build_view(
        game,
        user_id,
        demo_controls_enabled=service.manager.demo_controls_enabled,
    )


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
        request: Request,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        client_ip = request.client.host if request.client else None
        row = await service.join(session, user, body.join_code, client_ip=client_ip)
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
        return _view(service, game, user.id)

    @router.post("/games/{game_id}/arena")
    async def lobby_arena(
        game_id: UUID,
        body: LobbyCircleIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        game = await service.set_lobby_circle(
            session,
            user,
            game_id,
            radius_m=body.radius_m,
            center=body.center,
        )
        return _view(service, game, user.id)

    @router.post("/games/{game_id}/start")
    async def start(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        game = await service.start(session, user, game_id)
        return _view(service, game, user.id)

    @router.post("/games/{game_id}/pause")
    async def pause(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.pause(session, user, game_id), user.id)

    @router.post("/games/{game_id}/resume")
    async def resume(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.resume(session, user, game_id), user.id)

    @router.post("/games/{game_id}/end")
    async def end(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.end(session, user, game_id), user.id)

    @router.post("/games/{game_id}/rematch")
    async def rematch(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.rematch(session, user, game_id), user.id)

    @router.post("/games/{game_id}/leave")
    async def leave(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await service.leave(session, user, game_id)
        return {"ok": True, "game_id": str(row.id)}

    @router.post("/games/{game_id}/tags/qr")
    async def qr_tag(
        game_id: UUID,
        body: QrIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        # Return the seeker view so the scanner can drop the tagged pin without a tick wait.
        game = await service.qr_tag(session, user, game_id, body.token)
        return _view(service, game, user.id)

    @router.post("/games/{game_id}/players/{player_id}/remove")
    async def remove_player(
        game_id: UUID,
        player_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        game = await service.remove_player(session, user, game_id, player_id)
        return _view(service, game, user.id)

    @router.post("/games/{game_id}/tags/undo")
    async def undo_tag(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.undo_tag(session, user, game_id), user.id)

    @router.post("/games/{game_id}/power-ups")
    async def buy_power(
        game_id: UUID,
        body: dict[str, Any],
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        power_id = str(body.get("id", ""))
        extra = {k: v for k, v in body.items() if k != "id"}
        return _view(
            service, await service.purchase(session, user, game_id, power_id, extra), user.id
        )

    @router.post("/games/{game_id}/taunt")
    async def taunt(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.taunt(session, user, game_id), user.id)

    @router.post("/games/{game_id}/safety/ack")
    async def ack_safety(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return _view(service, await service.ack_safety(session, user, game_id), user.id)

    @router.get("/games/{game_id}/invite")
    async def invite(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row, _ = await service.require_member(session, game_id, user)
        await service.notify_invite(session, user, game_id)
        return {
            "join_code": row.join_code,
            "url": f"https://app.manhunt.ios/join/{row.join_code}",
        }

    @router.get("/games/{game_id}/trail")
    async def trail(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        return await service.read_trail(session, user, game_id)

    @router.get("/games/{game_id}/events")
    async def timeline(
        game_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        await service.require_member(session, game_id, user)
        # Flush the live session first. The tick loop is off in tests and may
        # not have written reveal / bounds / signal-loss rows yet.
        live = service.manager.get(game_id)
        if live is not None:
            await service.persist_game(session, live, commit=True)
        from sqlalchemy import select as sel

        from app.db.models import GameEventRow

        rows = (
            await session.execute(
                sel(GameEventRow)
                .where(GameEventRow.game_id == game_id, GameEventRow.sensitive.is_(False))
                .order_by(GameEventRow.seq)
            )
        ).scalars()
        return {"events": [{"seq": r.seq, "type": r.type, "payload": r.payload} for r in rows]}

    return router
