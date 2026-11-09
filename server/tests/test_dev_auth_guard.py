import pytest

from app.config import DevAuthMisconfigured, Settings


@pytest.mark.parametrize("env", ["azure", "prod"])
def test_dev_auth_refused_in_cloud_envs(env: str) -> None:
    settings = Settings(
        manhunt_env=env,
        manhunt_dev_auth=True,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
    )
    with pytest.raises(DevAuthMisconfigured):
        settings.validate_startup()


@pytest.mark.parametrize("env", ["local", "test", "home"])
def test_dev_auth_allowed_for_mvp(env: str) -> None:
    settings = Settings(
        manhunt_env=env,
        manhunt_dev_auth=True,
        manhunt_session_signing_key="x" * 32,
        manhunt_qr_signing_key="y" * 32,
    )
    settings.validate_startup()
