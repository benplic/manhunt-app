import pytest

from app.config import DevAuthMisconfigured, Settings


def _exposed(**overrides: object) -> Settings:
    """A home/cloud config with unique secrets, so one check can fail at a time."""
    values: dict[str, object] = {
        "manhunt_env": "home",
        "manhunt_dev_auth": True,
        "manhunt_dev_auth_secret": "home-party-secret",
        "manhunt_session_signing_key": "x" * 32,
        "manhunt_qr_signing_key": "y" * 32,
        "manhunt_trail_key": "cd" * 32,
        "manhunt_database_url": "postgresql+psycopg://manhunt:not-default@db:5432/manhunt",
    }
    values.update(overrides)
    return Settings(**values)  # type: ignore[arg-type]


@pytest.mark.parametrize("env", ["azure", "prod"])
def test_dev_auth_refused_in_cloud_envs(env: str) -> None:
    settings = _exposed(manhunt_env=env, manhunt_dev_auth=True)
    with pytest.raises(DevAuthMisconfigured):
        settings.validate_startup()


@pytest.mark.parametrize("env", ["local", "test"])
def test_dev_auth_allowed_for_local_and_test(env: str) -> None:
    settings = Settings(
        manhunt_env=env,
        manhunt_dev_auth=True,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
    )
    settings.validate_startup()


def test_home_dev_auth_boots_with_unique_secrets() -> None:
    _exposed().validate_startup()


def test_home_dev_auth_rejects_a_missing_party_secret(tmp_path) -> None:
    from fastapi.testclient import TestClient

    from app.main import create_app

    settings = _exposed(
        manhunt_tick_loop=False,
        manhunt_database_url=f"sqlite+aiosqlite:///{tmp_path / 'home.db'}",
    )
    with TestClient(create_app(settings)) as client:
        missing = client.post(
            "/v1/auth/dev",
            json={"display_name": "Casey", "installation_id": "phone-home-1", "age": 18},
        )
        assert missing.status_code == 403
        allowed = client.post(
            "/v1/auth/dev",
            json={"display_name": "Casey", "installation_id": "phone-home-1", "age": 18},
            headers={"X-Manhunt-Dev-Secret": "home-party-secret"},
        )
        assert allowed.status_code == 200, allowed.text


@pytest.mark.parametrize(
    "overrides",
    [
        {"manhunt_session_signing_key": "dev-session-signing-key-change-me"},
        {"manhunt_qr_signing_key": "dev-qr-signing-key-change-me"},
        {"manhunt_trail_key": "ab" * 32},
        {"manhunt_session_signing_key": "short"},
        {"manhunt_database_url": "postgresql+psycopg://manhunt:manhunt@db:5432/manhunt"},
        {"manhunt_dev_auth_secret": "too-short"},
        {"manhunt_dev_auth_secret": ""},
    ],
)
def test_exposed_env_rejects_published_defaults(overrides: dict) -> None:
    settings = _exposed(**overrides)
    with pytest.raises(DevAuthMisconfigured):
        settings.validate_startup()
