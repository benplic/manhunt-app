"""Join attempts are capped so a player cannot brute-force a 6-character code."""

from fastapi.testclient import TestClient


def _auth(client: TestClient, name: str) -> dict:
    response = client.post("/v1/auth/dev", json={"display_name": name})
    assert response.status_code == 200, response.text
    return response.json()


def _join(client: TestClient, token: str, code: str = "ABCDEF"):
    return client.post(
        "/v1/games/join",
        json={"join_code": code},
        headers={"Authorization": f"Bearer {token}"},
    )


def test_eleventh_join_in_a_minute_is_rate_limited(client: TestClient) -> None:
    casey = _auth(client, "Casey")
    riley = _auth(client, "Riley")

    for _ in range(10):
        response = _join(client, casey["access_token"])
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "GAME_NOT_FOUND"

    blocked = _join(client, casey["access_token"])
    assert blocked.status_code == 429
    assert blocked.json()["error"]["code"] == "RATE_LIMITED"

    # The cap is per user. A second player is not stuck behind Casey's misses.
    other = _join(client, riley["access_token"])
    assert other.status_code == 404
    assert other.json()["error"]["code"] == "GAME_NOT_FOUND"


def test_join_window_forgets_attempts_older_than_a_minute() -> None:
    from uuid import uuid4

    import pytest

    from app.errors import ApiError
    from app.games.join_limit import JoinRateLimiter

    now = [0.0]
    limiter = JoinRateLimiter(clock=lambda: now[0])
    user_id = uuid4()
    for _ in range(10):
        limiter.hit(user_id)
    with pytest.raises(ApiError) as caught:
        limiter.hit(user_id)
    assert caught.value.status_code == 429

    now[0] = 59.9
    with pytest.raises(ApiError):
        limiter.hit(user_id)

    now[0] = 60.0
    limiter.hit(user_id)
