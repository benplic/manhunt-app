"""Environment-backed settings. Secrets never belong in the repo."""

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class DevAuthMisconfigured(RuntimeError):
    """Dev sign-in must never be on in azure or prod."""


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    manhunt_env: Literal["local", "test", "home", "azure", "prod"] = "local"
    manhunt_database_url: str = "postgresql+psycopg://manhunt:manhunt@127.0.0.1:5432/manhunt"
    manhunt_session_signing_key: str = "dev-session-signing-key-change-me"
    manhunt_qr_signing_key: str = "dev-qr-signing-key-change-me"
    manhunt_apple_audience: str = "app.manhunt.ios"
    manhunt_dev_auth: bool = False
    manhunt_tick_loop: bool = True
    manhunt_trail_key: str = "ab" * 32
    manhunt_trail_key_id: str = "v1"
    manhunt_trail_retention_days: int = 7
    manhunt_self_ping_url: str = "http://127.0.0.1:8000/v1/healthz"
    manhunt_apns_key: str = ""
    manhunt_apns_key_id: str = ""
    manhunt_apns_team_id: str = ""
    manhunt_apns_bundle_id: str = "app.manhunt.ios"
    manhunt_apns_production: bool = False

    def validate_startup(self) -> None:
        """Refuse to boot if fake sign-in is enabled in a cloud environment."""
        if self.manhunt_dev_auth and self.manhunt_env in {"azure", "prod"}:
            raise DevAuthMisconfigured(
                "MANHUNT_DEV_AUTH cannot be true when MANHUNT_ENV is "
                f"{self.manhunt_env}. Use Sign in with Apple instead."
            )


def get_settings() -> Settings:
    return Settings()
