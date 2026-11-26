"""A phone that joins a hunt after it has started must be refused without a half-written seat."""

from uuid import UUID, uuid4

from fastapi.testclient import TestClient


def _auth(client: TestClient, name: str) -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(auth: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


def test_join_after_start_is_refused_and_leaves_no_membership(client: TestClient) -> None:
    host = _auth(client, "Host")
    guest = _auth(client, "Guest")
    late = _auth(client, "Latecomer")
    arena = client.post(
        "/v1/arenas",
        headers=_hdr(host),
        json={
            "name": "Park",
            "boundary": [
                {"lat": 40.663, "lon": -73.970},
                {"lat": 40.663, "lon": -73.968},
                {"lat": 40.661, "lon": -73.969},
            ],
            "zones": [],
        },
    ).json()
    game = client.post(
        "/v1/games",
        headers=_hdr(host),
        json={"arena_id": arena["id"], "preset_id": "classic", "overrides": {}},
    ).json()
    gid, code = game["id"], game["join_code"]
    client.post("/v1/games/join", headers=_hdr(guest), json={"join_code": code})
    view = client.get(f"/v1/games/{gid}", headers=_hdr(host)).json()
    host_id = view["you"]["player_id"]
    guest_id = next(p["player_id"] for p in view["players"] if p["player_id"] != host_id)
    roles = client.post(
        f"/v1/games/{gid}/roles",
        headers=_hdr(host),
        json={"mode": "manual", "assignments": {host_id: "seeker", guest_id: "hider"}},
    )
    assert roles.status_code == 200, roles.text
    started = client.post(f"/v1/games/{gid}/start", headers=_hdr(host))
    assert started.status_code == 200, started.text

    joined = client.post("/v1/games/join", headers=_hdr(late), json={"join_code": code})
    assert joined.status_code == 409, joined.text
    assert joined.json()["error"]["code"] == "WRONG_PHASE"

    session = client.app.state.manager.get(UUID(gid))
    assert session is not None
    assert late["user"]["id"] not in {str(pid) for pid in session.state.players}
    refused = client.get(f"/v1/games/{gid}", headers=_hdr(late))
    assert refused.status_code == 403
