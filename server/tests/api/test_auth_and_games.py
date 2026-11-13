from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from tests.engine.helpers import meters, square


def _auth(client: TestClient, name: str = "Casey") -> dict:
    response = client.post("/v1/auth/dev", json={"display_name": name})
    assert response.status_code == 200, response.text
    return response.json()


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_apple_rejects_garbage(client: TestClient) -> None:
    response = client.post("/v1/auth/apple", json={"identity_token": "nope"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "TOKEN_INVALID"


def test_refresh_rotates(client: TestClient) -> None:
    first = client.post("/v1/auth/dev", json={"display_name": "Casey"})
    assert first.status_code == 200
    body = first.json()
    assert body.get("refresh_token")
    rotated = client.post("/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert rotated.status_code == 200, rotated.text
    assert rotated.json()["refresh_token"] != body["refresh_token"]
    replay = client.post("/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert replay.status_code == 401


def test_create_join_start_needs_both_roles(client: TestClient) -> None:
    host = _auth(client, "Casey")
    guest = _auth(client, "Riley")
    arena_body = arena_to_dict(square())
    created = client.post("/v1/arenas", json=arena_body, headers=_headers(host["access_token"]))
    assert created.status_code == 200, created.text
    arena_id = created.json()["id"]
    game = client.post(
        "/v1/games",
        json={
            "arena_id": arena_id,
            "preset_id": "classic",
            "overrides": {"head_start": {"duration": 15}},
        },
        headers=_headers(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    join_code = game.json()["join_code"]
    game_id = game.json()["id"]
    joined = client.post(
        "/v1/games/join",
        json={"join_code": join_code.lower()},
        headers=_headers(guest["access_token"]),
    )
    assert joined.status_code == 200
    start = client.post(f"/v1/games/{game_id}/start", headers=_headers(host["access_token"]))
    assert start.status_code == 409
    assert start.json()["error"]["code"] == "NEED_BOTH_ROLES"
    roles = client.post(
        f"/v1/games/{game_id}/roles",
        json={"mode": "random", "seeker_count": 1},
        headers=_headers(host["access_token"]),
    )
    assert roles.status_code == 200
    start = client.post(f"/v1/games/{game_id}/start", headers=_headers(host["access_token"]))
    assert start.status_code == 200, start.text
    assert start.json()["phase"] in {"head_start", "active"}


def test_invalid_arena_rejected(client: TestClient) -> None:
    host = _auth(client)
    response = client.post(
        "/v1/arenas",
        json={
            "name": "Line",
            "boundary": [{"lat": 0, "lon": 0}, {"lat": 1, "lon": 0}],
            "zones": [],
        },
        headers=_headers(host["access_token"]),
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "ARENA_INVALID"


def test_circle_arena_crud_roundtrip_and_radius_validation(client: TestClient) -> None:
    host = _auth(client)
    headers = _headers(host["access_token"])
    bad = client.post(
        "/v1/arenas",
        json={
            "name": "Too small",
            "boundary": [],
            "boundary_circle": {"center": {"lat": 40.6616, "lon": -73.9688}, "radius_m": 10},
            "zones": [],
        },
        headers=headers,
    )
    assert bad.status_code == 422
    assert bad.json()["error"]["code"] == "ARENA_INVALID"

    created = client.post(
        "/v1/arenas",
        json={
            "name": "Meadow Circle",
            "boundary": [
                {"lat": 0.0, "lon": 0.0},
                {"lat": 0.1, "lon": 0.0},
                {"lat": 0.0, "lon": 0.1},
            ],
            "boundary_circle": {"center": {"lat": 40.6616, "lon": -73.9688}, "radius_m": 200},
            "zones": [],
        },
        headers=headers,
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["boundary_circle"] == {
        "center": {"lat": 40.6616, "lon": -73.9688},
        "radius_m": 200.0,
    }
    assert len(body["boundary"]) == 64
    fetched = client.get(f"/v1/arenas/{body['id']}", headers=headers)
    assert fetched.status_code == 200
    assert fetched.json()["boundary_circle"] == body["boundary_circle"]
    assert len(fetched.json()["boundary"]) == 64



def test_join_unknown_code(client: TestClient) -> None:
    user = _auth(client)
    response = client.post(
        "/v1/games/join",
        json={"join_code": "ABCDEF"},
        headers=_headers(user["access_token"]),
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "GAME_NOT_FOUND"


def test_presets_lists_classic(client: TestClient) -> None:
    response = client.get("/v1/presets")
    assert response.status_code == 200
    assert response.json()[0]["id"] == "classic"


def test_me_requires_auth(client: TestClient) -> None:
    assert client.get("/v1/me").status_code == 401
    user = _auth(client, "Quinn")
    me = client.get("/v1/me", headers=_headers(user["access_token"]))
    assert me.status_code == 200
    assert me.json()["display_name"] == "Quinn"


def test_meters_helper_still_imports() -> None:
    point = meters(0, 0)
    assert point.lat == 0
