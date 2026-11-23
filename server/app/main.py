"""FastAPI entrypoint. Keep this module the composition root."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.arenas.routes import bind_arena_routes
from app.auth.deps import bind_current_user
from app.auth.routes import bind_auth_routes, bind_me_routes
from app.config import Settings, get_settings
from app.db.models import GameRow
from app.db.session import create_schema, lifespan_resources
from app.demo.routes import bind_demo_routes
from app.errors import ApiError, ErrorCode, GameRuleError
from app.games.routes import bind_game_routes
from app.games.service import GameService
from app.jobs.purge import purge_trails
from app.logging_setup import configure_logging
from app.presets.routes import router as presets_router
from app.realtime.manager import SessionManager
from app.realtime.ws import bind_ws
from app.schemas.routes import bind_preset_save
from app.schemas.routes import router as modules_router

log = logging.getLogger("manhunt.main")


def _error_json(
    status_code: int, *, code: str, message: str, details: dict
) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message, "details": details}},
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    settings.validate_startup()
    configure_logging(settings.manhunt_env)

    engine, factory = lifespan_resources(settings)
    manager = SessionManager(
        qr_key=settings.manhunt_qr_signing_key,
        demo_controls_enabled=settings.demo_controls_enabled,
    )
    service = GameService(manager)

    async def get_session() -> AsyncIterator[AsyncSession]:
        async with factory() as session:
            yield session

    def settings_dep() -> Settings:
        return settings

    current_user = bind_current_user(get_session, settings_dep)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        await create_schema(engine)
        async with factory() as session:
            from app.crypto import TrailKeyError, load_trail_key, open_inputs
            from app.engine.arena import arena_from_dict
            from app.engine.recovery import rebuild_session

            try:
                trail_key = load_trail_key(settings.manhunt_trail_key)
            except TrailKeyError:
                trail_key = None

            rows = (
                await session.execute(
                    select(GameRow).where(
                        GameRow.status.in_(["head_start", "active", "paused", "lobby"])
                    )
                )
            ).scalars()
            restored = 0
            for row in rows:
                if row.join_code == "PARK42":
                    # TODO: persist demo snapshot if sample lobbies ever need crash
                    # recovery across restarts.
                    row.status = "abandoned"
                    continue
                if row.inputs:
                    try:
                        logged = open_inputs(trail_key, row.inputs)
                        game = rebuild_session(
                            game_id=row.id,
                            arena=arena_from_dict(row.arena_snapshot),
                            preset=row.preset_snapshot,
                            seed=row.seed,
                            join_code=row.join_code,
                            inputs=logged,
                            qr_key=settings.manhunt_qr_signing_key,
                        )
                    except Exception:
                        # A single broken trail (e.g. move_safe to a missing zone)
                        # must not keep the home server from booting.
                        log.exception("game_rebuild_failed game_id=%s", row.id)
                        row.status = "abandoned"
                        continue
                    manager.sessions[row.id] = game
                    restored += 1
                elif row.status in {"head_start", "active", "paused"}:
                    # No inputs to replay; mark abandoned so we never silently invent state.
                    row.status = "abandoned"
            await session.commit()
            _ = restored
        async with factory() as session:
            try:
                await purge_trails(session, settings.manhunt_trail_retention_days)
            except Exception:
                log.exception("trail_purge_failed")

        async def persist_all() -> None:
            # One session/commit per game so a single failure cannot dirty the rest.
            for game in list(manager.sessions.values()):
                async with factory() as session:
                    try:
                        await service.persist_game(session, game, commit=True)
                    except Exception:
                        await session.rollback()
                        log.exception(
                            "persist_game_failed game_id=%s", game.state.game_id
                        )

        async def keep_alive() -> None:
            # Loopback HTTP so ACA request concurrency stays above zero.
            async with httpx.AsyncClient() as client:
                await client.get(settings.manhunt_self_ping_url, timeout=5.0)

        task = None
        purge_task = None
        if settings.manhunt_tick_loop:
            task = asyncio.create_task(
                manager.tick_loop(True, keep_alive=keep_alive, persist=persist_all)
            )

            async def daily_purge() -> None:
                while True:
                    await asyncio.sleep(24 * 3600)
                    try:
                        async with factory() as session:
                            await purge_trails(session, settings.manhunt_trail_retention_days)
                    except Exception:
                        log.exception("trail_purge_failed")

            purge_task = asyncio.create_task(daily_purge())
        yield
        if task:
            task.cancel()
        if purge_task:
            purge_task.cancel()
        await engine.dispose()

    # The public Azure ingress should not serve the interactive schema.
    public_docs = None if settings.manhunt_env in {"azure", "prod"} else "/docs"
    app = FastAPI(
        title="Manhunt",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=public_docs,
        redoc_url=None if public_docs is None else "/redoc",
        openapi_url=None if public_docs is None else "/openapi.json",
    )
    app.state.settings = settings
    app.state.manager = manager
    app.state.session_factory = factory

    # Static web client (Vite / Cloudflare Pages) talks to this API cross-origin.
    # Add the Pages hostname via MANHUNT_CORS_ORIGINS when the site is published.
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "X-Manhunt-Dev-Secret"],
        )

    @app.exception_handler(ApiError)
    async def api_error_handler(_request: Request, exc: ApiError) -> JSONResponse:
        return _error_json(
            exc.status_code,
            code=exc.code.value,
            message=exc.message,
            details=exc.details,
        )

    @app.exception_handler(GameRuleError)
    async def rule_error_handler(_request: Request, exc: GameRuleError) -> JSONResponse:
        return _error_json(409, code=exc.code.value, message=exc.message, details={})

    @app.get("/.well-known/apple-app-site-association")
    @app.get("/apple-app-site-association")
    async def apple_app_site_association() -> JSONResponse:
        """Universal-link association for https://app.manhunt.ios/join/{code}.

        The invite host must serve this file with no redirect. The app id is the
        Xcode team's id plus the bundle id the project signs.
        """
        return JSONResponse(
            {
                "applinks": {
                    "details": [
                        {
                            "appIDs": ["H366S3X2VW.app.manhunt.ios"],
                            "components": [
                                {"/": "/join/*", "comment": "Invite link and invite QR"}
                            ],
                        }
                    ]
                }
            }
        )

    @app.get("/healthz")
    @app.get("/v1/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz")
    @app.get("/v1/readyz")
    async def readyz() -> dict[str, str | int]:
        active = sum(
            1
            for s in manager.sessions.values()
            if s.state.phase in {"lobby", "head_start", "active", "paused"}
        )
        return {"status": "ok", "active_games": active}

    app.include_router(bind_auth_routes(get_session, settings_dep, current_user))
    app.include_router(bind_me_routes(get_session, current_user))
    app.include_router(bind_arena_routes(get_session, current_user))
    app.include_router(presets_router)
    app.include_router(modules_router)
    app.include_router(bind_preset_save(get_session, current_user))
    async def persist_location(game) -> None:
        async with factory() as session:
            await service.persist_game(session, game, commit=True)

    app.include_router(bind_game_routes(get_session, current_user, service))
    app.include_router(bind_demo_routes(get_session, current_user, service, settings_dep))
    app.include_router(bind_ws(manager, settings_dep, persist_location=persist_location))
    # APPLICATIONINSIGHTS_CONNECTION_STRING is injected by Container Apps when
    # the Bicep Insights resource exists. Portal metrics use it; we do not
    # pull the OpenTelemetry SDK into this process.
    _ = Depends, select, ErrorCode
    return app


app = create_app()
