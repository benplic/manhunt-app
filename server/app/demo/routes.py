"""FastAPI router for PARK42 demo controls."""

from __future__ import annotations

import logging
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict
from sqlalchemy.ext.asyncio import AsyncSession

from app.demo.controls import apply_demo_action
from app.engine.views import build_view
from app.errors import ApiError, ErrorCode, GameRuleError
from app.games.service import GameService

log = logging.getLogger("manhunt.demo")


class DemoActionIn(BaseModel):
    model_config = ConfigDict(extra="allow")
    action: str


def bind_demo_routes(get_session, current_user, service: GameService, get_settings):
    router = APIRouter(prefix="/v1", tags=["demo"])

    @router.post("/games/{game_id}/demo")
    async def demo_action(
        game_id: UUID,
        body: DemoActionIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict[str, Any]:
        settings = get_settings()
        if not settings.demo_controls_enabled:
            raise ApiError(ErrorCode.GAME_NOT_FOUND, "Not found.", status_code=404)

        await service.require_member(session, game_id, user)
        game = service.manager.get(game_id)
        if game is None or game.demo is None:
            raise ApiError(
                ErrorCode.GAME_NOT_FOUND,
                "Demo controls are only available in the sample lobby.",
                status_code=404,
            )

        player = game.state.players.get(user.id)
        if player is None:
            raise ApiError(ErrorCode.NOT_A_MEMBER, "You are not in this game.", status_code=403)
        if body.action != "move_me" and not player.is_host:
            raise ApiError(
                ErrorCode.NOT_HOST, "Only the host can use demo controls.", status_code=403
            )

        params = body.model_dump(exclude={"action"})
        # Never log coordinates or tokens; action name + game_id only.
        log.info("demo_action game_id=%s action=%s", game_id, body.action)
        try:
            apply_demo_action(game, user.id, body.action, params)
        except GameRuleError as exc:
            status = 422 if exc.code == ErrorCode.VALIDATION_FAILED else 409
            raise ApiError(exc.code, exc.message, status_code=status) from exc

        await service.persist_game(session, game)
        await session.commit()
        await service.manager.broadcast(game_id)
        return build_view(
            game,
            user.id,
            demo_controls_enabled=settings.demo_controls_enabled,
        )

    return router
