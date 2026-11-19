"""Host can resize the play circle while the hunt is still in lobby."""

from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient


def _auth(client: TestClient, name: str = "Host") -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_host_resizes_lobby_circle(client: TestClient) -> None:
    host = _auth(client, "Host")
    headers = _headers(host["access_token"])
    arena = client.post(
        "/v1/arenas",
        headers=headers,
        json={
            "name": "Park",
            "boundary": [],
            "boundary_circle": {"center": {"lat": 40.6616, "lon": -73.9688}, "radius_m": 400},
            "zones": [],
        },
    )
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        headers=headers,
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
    )
    assert game.status_code == 200, game.text
    gid = game.json()["id"]

    resized = client.post(
        f"/v1/games/{gid}/arena",
        headers=headers,
        json={"radius_m": 800},
    )
    assert resized.status_code == 200, resized.text
    circle = resized.json()["arena"]["boundary_circle"]
    assert circle["radius_m"] == 800
    assert circle["center"]["lat"] == 40.6616

    guest = _auth(client, "Guest")
    denied = client.post(
        f"/v1/games/{gid}/arena",
        headers=_headers(guest["access_token"]),
        json={"radius_m": 500},
    )
    assert denied.status_code == 403
