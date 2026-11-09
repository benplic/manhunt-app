from fastapi.testclient import TestClient

from tests.conftest import make_test_app


def test_healthz_ok(tmp_path) -> None:
    app = make_test_app(tmp_path)
    client = TestClient(app)
    for path in ("/healthz", "/v1/healthz"):
        response = client.get(path)
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
