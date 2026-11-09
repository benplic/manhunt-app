"""FastAPI entrypoint. Keep this module thin; routes live in their packages."""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.config import Settings, get_settings
from app.errors import ApiError, ErrorCode, GameRuleError
from app.logging_setup import configure_logging


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    settings.validate_startup()
    configure_logging(settings.manhunt_env)

    app = FastAPI(title="Manhunt", version="0.1.0")
    app.state.settings = settings

    @app.exception_handler(ApiError)
    async def api_error_handler(_request: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": {
                    "code": exc.code.value,
                    "message": exc.message,
                    "details": exc.details,
                }
            },
        )

    @app.exception_handler(GameRuleError)
    async def rule_error_handler(_request: Request, exc: GameRuleError) -> JSONResponse:
        return JSONResponse(
            status_code=409,
            content={
                "error": {
                    "code": exc.code.value,
                    "message": exc.message,
                    "details": {},
                }
            },
        )

    @app.get("/healthz")
    @app.get("/v1/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz")
    @app.get("/v1/readyz")
    async def readyz() -> dict[str, str]:
        # TODO: Phase 2 report active game count so deploys can wait.
        return {"status": "ok"}

    # Silence unused import until auth routes register ErrorCode.INTERNAL.
    _ = ErrorCode.INTERNAL
    return app


app = create_app()
