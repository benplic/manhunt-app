from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str = "Casey") -> dict:
    return client.post("/v1/auth/dev", json={"display_name": name}).json()


def test_modules_schema_lists_classic_ids(client: TestClient) -> None:
    response = client.get("/v1/modules")
    assert response.status_code == 200
    body = response.json()
    ids = set(body["modules"].keys())
    assert {"roles", "head_start", "power_ups", "reveal_fuzzy", "zone_shrink"} <= ids
    location_mode = body["modules"]["reveal_fuzzy"]["fields"]["location_mode"]
    assert location_mode["values"] == ["fuzzy", "precise", "hot_cold"]
    # The preset editor renders this document. Order and bounds are part of it.
    assert body["order"][0] == "roles"
    assert set(body["modules"]["zone_shrink"]["fields"]) == {
        "enabled",
        "every",
        "shrink_to",
        "min_radius_m",
    }
    duration = body["modules"]["head_start"]["fields"]["duration"]
    assert duration["min"] == 15
    assert duration["max"] == 600
    assert duration["default"] == 60
    association = client.get("/.well-known/apple-app-site-association")
    assert association.status_code == 200
    details = association.json()["applinks"]["details"][0]
    assert "H366S3X2VW.app.manhunt.ios" in details["appIDs"]
    assert details["components"][0]["/"] == "/join/*"


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


def test_saved_preset_can_be_renamed_and_deleted(client: TestClient) -> None:
    host = _auth(client)
    headers = {"Authorization": f"Bearer {host['access_token']}"}
    saved = client.post(
        "/v1/presets/saved",
        json={"name": "Park night", "modules": {"head_start": {"duration": 45}}},
        headers=headers,
    )
    preset_id = saved.json()["id"]
    renamed = client.put(
        f"/v1/presets/saved/{preset_id}",
        json={"name": "Park dawn", "modules": {"head_start": {"duration": 30}}},
        headers=headers,
    )
    assert renamed.status_code == 200
    assert renamed.json()["name"] == "Park dawn"
    assert renamed.json()["modules"]["head_start"]["duration"] == 30
    other = _auth(client, "Riley")
    forbidden = client.delete(
        f"/v1/presets/saved/{preset_id}",
        headers={"Authorization": f"Bearer {other['access_token']}"},
    )
    assert forbidden.status_code == 403
    deleted = client.delete(f"/v1/presets/saved/{preset_id}", headers=headers)
    assert deleted.status_code == 200
    listed = client.get("/v1/presets/saved", headers=headers)
    assert listed.json() == []


def test_overhanging_circle_arena_clips_on_create(client: TestClient) -> None:
    host = _auth(client)
    headers = {"Authorization": f"Bearer {host['access_token']}"}
    arena = arena_to_dict(square())
    arena["zones"] = [
        {
            "id": "00000000-0000-0000-0000-00000000cc01",
            "name": "Fountain",
            "kind": "safe",
            "shape": {
                "type": "circle",
                "center": {"lat": arena["boundary"][2]["lat"], "lon": arena["boundary"][2]["lon"]},
                "radius_m": 500,
            },
        }
    ]
    response = client.post("/v1/arenas", json=arena, headers=headers)
    assert response.status_code == 200, response.text
    shape = response.json()["zones"][0]["shape"]
    assert shape["type"] == "polygon"

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


def test_zone_shrink_requires_circle_arena_on_create(client: TestClient) -> None:
    host = _auth(client)
    headers = {"Authorization": f"Bearer {host['access_token']}"}
    polygon_arena = client.post("/v1/arenas", json=arena_to_dict(square()), headers=headers).json()
    rejected_poly = client.post(
        "/v1/games",
        json={
            "arena_id": polygon_arena["id"],
            "preset_id": "classic",
            "overrides": {"zone_shrink": {"enabled": True}},
        },
        headers=headers,
    )
    assert rejected_poly.status_code == 422
    assert rejected_poly.json()["error"]["code"] == "VALIDATION_FAILED"
    assert rejected_poly.json()["error"]["details"]["field"] == "zone_shrink.enabled"

    circle_arena = client.post(
        "/v1/arenas",
        json={
            "name": "Circle Park",
            "boundary": [],
            "boundary_circle": {"center": {"lat": 40.6616, "lon": -73.9688}, "radius_m": 200},
            "zones": [],
        },
        headers=headers,
    ).json()
    rejected_min = client.post(
        "/v1/games",
        json={
            "arena_id": circle_arena["id"],
            "preset_id": "classic",
            "overrides": {"zone_shrink": {"enabled": True, "min_radius_m": 250}},
        },
        headers=headers,
    )
    assert rejected_min.status_code == 422
    assert rejected_min.json()["error"]["code"] == "VALIDATION_FAILED"
    assert rejected_min.json()["error"]["details"]["field"] == "zone_shrink.min_radius_m"

    accepted = client.post(
        "/v1/games",
        json={
            "arena_id": circle_arena["id"],
            "preset_id": "classic",
            "overrides": {"zone_shrink": {"enabled": True, "min_radius_m": 50}},
        },
        headers=headers,
    )
    assert accepted.status_code == 200, accepted.text

