"""Environment-backed settings. Secrets never belong in the repo."""

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class DevAuthMisconfigured(RuntimeError):
    """Dev sign-in must never be on in azure or prod."""


# Strings that have shipped in git. A home or cloud process must not sign
# sessions, QR codes, or location trails with them.
KNOWN_INSECURE_SECRETS = frozenset(
    {
        "dev-session-signing-key-change-me",
        "dev-qr-signing-key-change-me",
        "ci-session-signing-key-change-me",
        "ci-qr-signing-key-change-me",
        "test-session-signing-key-change-me",
        "test-qr-signing-key-change-me",
        "replace-in-pipeline",
        "replace-with-a-long-random-string",
        "replace-with-a-different-long-random-string",
        "replace-with-64-hex-chars",
        "ab" * 32,
    }
)

# Environments that can be reached past the developer's laptop.
_EXPOSED_ENVS = frozenset({"home", "azure", "prod"})


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    manhunt_env: Literal["local", "test", "home", "azure", "prod"] = "local"
    manhunt_database_url: str = "postgresql+psycopg://manhunt:manhunt@127.0.0.1:5432/manhunt"
    manhunt_session_signing_key: str = "dev-session-signing-key-change-me"
    manhunt_qr_signing_key: str = "dev-qr-signing-key-change-me"
    manhunt_apple_audience: str = "app.manhunt.ios"
    manhunt_dev_auth: bool = False
    # Shared party secret for POST /v1/auth/dev. Required when that route is
    # on in the home profile, which home-server.sh publishes through a tunnel.
    manhunt_dev_auth_secret: str = ""
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
    manhunt_demo_controls: bool | None = None
    # Comma-separated browser origins for the static web client (Vite + Pages).
    manhunt_cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"

    @property
    def demo_controls_enabled(self) -> bool:
        if self.manhunt_demo_controls is not None:
            return self.manhunt_demo_controls
        return self.manhunt_env in {"local", "test", "home"}

    @property
    def cors_origins(self) -> list[str]:
        return [part.strip() for part in self.manhunt_cors_origins.split(",") if part.strip()]

    def validate_startup(self) -> None:
        """Refuse to boot if fake sign-in or a published default secret is on."""
        if self.manhunt_dev_auth and self.manhunt_env in {"azure", "prod"}:
            raise DevAuthMisconfigured(
                "MANHUNT_DEV_AUTH cannot be true when MANHUNT_ENV is "
                f"{self.manhunt_env}. Use Sign in with Apple instead."
            )
        if self.manhunt_env not in _EXPOSED_ENVS:
            return
        for name, value in (
            ("MANHUNT_SESSION_SIGNING_KEY", self.manhunt_session_signing_key),
            ("MANHUNT_QR_SIGNING_KEY", self.manhunt_qr_signing_key),
            ("MANHUNT_TRAIL_KEY", self.manhunt_trail_key),
        ):
            if value in KNOWN_INSECURE_SECRETS or len(value) < 32:
                raise DevAuthMisconfigured(
                    f"{name} is still a known default. Set a unique secret before "
                    f"starting MANHUNT_ENV={self.manhunt_env}."
                )
        if ":manhunt@" in self.manhunt_database_url:
            raise DevAuthMisconfigured(
                "The database URL still uses the password 'manhunt'. "
                "Set POSTGRES_PASSWORD and MANHUNT_DATABASE_URL."
            )
        if self.manhunt_dev_auth and len(self.manhunt_dev_auth_secret) < 16:
            raise DevAuthMisconfigured(
                "MANHUNT_DEV_AUTH_SECRET must be at least 16 characters when "
                "dev sign-in is enabled for a home server."
            )
        if self.manhunt_dev_auth_secret and self.manhunt_dev_auth_secret in KNOWN_INSECURE_SECRETS:
            raise DevAuthMisconfigured("MANHUNT_DEV_AUTH_SECRET is still a placeholder.")


def get_settings() -> Settings:
    return Settings()
