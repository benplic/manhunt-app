"""Shared pytest fixtures. Tests must not depend on a running Docker daemon."""

import os

import pytest

os.environ.setdefault("MANHUNT_ENV", "test")
os.environ.setdefault("MANHUNT_DEV_AUTH", "true")
os.environ.setdefault("MANHUNT_TICK_LOOP", "false")


@pytest.fixture
def settings_kwargs() -> dict[str, object]:
    return {
        "manhunt_session_signing_key": "x" * 32,
        "manhunt_qr_signing_key": "y" * 32,
    }
