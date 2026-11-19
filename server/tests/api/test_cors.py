"""Browser preflight for the static web client."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from tests.conftest import make_test_app


def test_preflight_allows_localhost_vite_origin(tmp_path: Path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        response = client.options(
            "/v1/auth/dev",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type,x-manhunt-dev-secret",
            },
        )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:5173"
    allowed = response.headers.get("access-control-allow-headers", "").lower()
    assert "authorization" in allowed
    assert "x-manhunt-dev-secret" in allowed


def test_preflight_allows_configured_pages_origin(tmp_path: Path) -> None:
    from app.config import Settings
    from app.engine.clock import FakeClock
    from app.main import create_app

    db = tmp_path / "cors.db"
    settings = Settings(
        manhunt_env="test",
        manhunt_dev_auth=True,
        manhunt_tick_loop=False,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
        manhunt_database_url=f"sqlite+aiosqlite:///{db}",
        manhunt_cors_origins="http://localhost:5173,https://manhunt-web.pages.dev",
    )
    application = create_app(settings)
    application.state.manager.clock = FakeClock()
    with TestClient(application) as client:
        response = client.options(
            "/v1/healthz",
            headers={
                "Origin": "https://manhunt-web.pages.dev",
                "Access-Control-Request-Method": "GET",
            },
        )
    assert response.status_code == 200
    assert (
        response.headers.get("access-control-allow-origin")
        == "https://manhunt-web.pages.dev"
    )


def test_unknown_origin_is_not_reflected(tmp_path: Path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        response = client.options(
            "/v1/healthz",
            headers={
                "Origin": "https://evil.example",
                "Access-Control-Request-Method": "GET",
            },
        )
    # Starlette still answers OPTIONS; it must not echo a disallowed Origin.
    assert response.headers.get("access-control-allow-origin") != "https://evil.example"
