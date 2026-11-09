"""Shared pytest fixtures. Tests must not depend on a running Docker daemon."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.engine.clock import FakeClock
from app.main import create_app

os.environ.setdefault("MANHUNT_ENV", "test")
os.environ.setdefault("MANHUNT_DEV_AUTH", "true")
os.environ.setdefault("MANHUNT_TICK_LOOP", "false")


def make_test_app(tmp_path: Path):
    db = tmp_path / "manhunt.db"
    settings = Settings(
        manhunt_env="test",
        manhunt_dev_auth=True,
        manhunt_tick_loop=False,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
        manhunt_database_url=f"sqlite+aiosqlite:///{db}",
    )
    application = create_app(settings)
    application.state.manager.clock = FakeClock()
    return application


@pytest.fixture
def app(tmp_path: Path):
    return make_test_app(tmp_path)


@pytest.fixture
def client(app) -> TestClient:
    with TestClient(app) as test_client:
        yield test_client
