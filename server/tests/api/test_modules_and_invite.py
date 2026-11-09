from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str = "Casey") -> dict:
    return client.post("/v1/auth/dev", json={"display_name": name}).json()


def test_modules_schema_lists_classic_ids(client: TestClient) -> None:
    response = client.get("/v1/modules")
    assert response.status_code == 200
    ids = set(response.json()["modules"].keys())
    assert {"roles", "head_start", "power_ups", "hot_cold"} <= ids


def test_saved_preset_and_invite(client: TestClient) -> None:
    host = _auth(client)
    headers = {"Authorization": f"Bearer {host['access_token']}"}
    saved = client.post(
        "/v1/presets/saved",
        json={"name": "Park night", "modules": {"head_start": {"duration": 45}}},
        headers=headers,
    )
    assert saved.status_code == 200, saved.text
    listed = client.get("/v1/presets/saved", headers=headers)
    assert listed.json()[0]["name"] == "Park night"

    arena = client.post("/v1/arenas", json=arena_to_dict(square()), headers=headers)
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic"},
        headers=headers,
    )
    game_id = game.json()["id"]
    invite = client.get(f"/v1/games/{game_id}/invite", headers=headers)
    assert invite.status_code == 200
    assert invite.json()["join_code"] == game.json()["join_code"]
    assert invite.json()["url"].endswith(game.json()["join_code"])
