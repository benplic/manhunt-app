"""Tonight-only name sign-in: the same display name on two installs is one account.

Covers the playtest mode behind MANHUNT_NAME_SIGN_IN. Arenas and saved rule
presets are owner-scoped, so reusing the account is what shares them.
"""

from __future__ import annotations

from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.engine.arena import arena_to_dict
from app.main import create_app
from tests.engine.helpers import square

PARTY_KEY = "party-key-for-tests-1234"


@pytest.fixture
def name_client(tmp_path: Path):
    settings = Settings(
        manhunt_env="test",
        manhunt_dev_auth=True,
        manhunt_tick_loop=False,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
        manhunt_database_url=f"sqlite+aiosqlite:///{tmp_path / 'names.db'}",
        manhunt_dev_auth_secret=PARTY_KEY,
        manhunt_name_sign_in=True,
        manhunt_playtest_log_dir="",
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def _signin(client: TestClient, name: str, install: str | None = None, key: str = PARTY_KEY):
    return client.post(
        "/v1/auth/dev",
        json={
            "display_name": name,
            "installation_id": install or str(uuid4()),
            "age": 18,
        },
        headers={"X-Manhunt-Dev-Secret": key},
    )


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_same_name_on_two_installs_is_the_same_account(name_client: TestClient) -> None:
    phone = _signin(name_client, "Benny", install="install-phone-aaaa").json()
    laptop = _signin(name_client, "Benny", install="install-laptop-bbbb").json()
    assert phone["user"]["id"] == laptop["user"]["id"]


def test_name_match_ignores_case_and_extra_spaces(name_client: TestClient) -> None:
    first = _signin(name_client, "Benny Plichta", install="install-one-aaaa").json()
    second = _signin(name_client, "  benny   PLICHTA ", install="install-two-bbbb").json()
    assert first["user"]["id"] == second["user"]["id"]


def test_arena_from_first_install_is_listed_on_second(name_client: TestClient) -> None:
    phone = _signin(name_client, "Benny", install="install-phone-aaaa").json()
    created = name_client.post(
        "/v1/arenas", json=arena_to_dict(square()), headers=_bearer(phone["access_token"])
    )
    assert created.status_code == 200, created.text

    laptop = _signin(name_client, "Benny", install="install-laptop-bbbb").json()
    listed = name_client.get("/v1/arenas", headers=_bearer(laptop["access_token"]))
    assert listed.status_code == 200
    assert [row["id"] for row in listed.json()] == [created.json()["id"]]


def test_saved_rule_preset_from_first_install_is_listed_on_second(name_client: TestClient) -> None:
    phone = _signin(name_client, "Benny", install="install-phone-aaaa").json()
    saved = name_client.post(
        "/v1/presets/saved",
        json={"name": "Park rules", "modules": {"head_start": {"duration": 90}}},
        headers=_bearer(phone["access_token"]),
    )
    assert saved.status_code == 200, saved.text

    laptop = _signin(name_client, "Benny", install="install-laptop-bbbb").json()
    listed = name_client.get("/v1/presets/saved", headers=_bearer(laptop["access_token"]))
    assert listed.status_code == 200
    assert [row["name"] for row in listed.json()] == ["Park rules"]


def test_different_names_stay_separate_accounts(name_client: TestClient) -> None:
    benny = _signin(name_client, "Benny", install="install-phone-aaaa").json()
    riley = _signin(name_client, "Riley", install="install-phone-cccc").json()
    assert benny["user"]["id"] != riley["user"]["id"]


def test_name_sign_in_still_requires_the_party_key(name_client: TestClient) -> None:
    missing = _signin(name_client, "Benny", key="")
    assert missing.status_code == 403
    wrong = _signin(name_client, "Benny", key="not-the-party-key-0000")
    assert wrong.status_code == 403


def test_default_settings_keep_install_keyed_accounts(tmp_path: Path) -> None:
    settings = Settings(
        manhunt_env="test",
        manhunt_dev_auth=True,
        manhunt_tick_loop=False,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
        manhunt_database_url=f"sqlite+aiosqlite:///{tmp_path / 'default.db'}",
        manhunt_playtest_log_dir="",
    )
    with TestClient(create_app(settings)) as client:
        phone = _signin(client, "Benny", install="install-phone-aaaa", key="").json()
        laptop = _signin(client, "Benny", install="install-laptop-bbbb", key="").json()
    assert phone["user"]["id"] != laptop["user"]["id"]
