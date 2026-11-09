from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_healthz_ok() -> None:
    app = create_app(
        Settings(
            manhunt_env="test",
            manhunt_dev_auth=True,
            manhunt_session_signing_key="x" * 32,
            manhunt_qr_signing_key="y" * 32,
        )
    )
    client = TestClient(app)
    for path in ("/healthz", "/v1/healthz"):
        response = client.get(path)
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
