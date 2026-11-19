"""Host rematch opens a new lobby from an ended game's arena + preset."""

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str = "Casey") -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _ended_game(client: TestClient, host: dict) -> dict:
    headers = _headers(host["access_token"])
    arena = client.post(
        "/v1/arenas",
        json=arena_to_dict(square()),
        headers=headers,
    )
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        json={
            "arena_id": arena.json()["id"],
            "preset_id": "classic",
            "overrides": {"head_start": {"duration": 15}},
        },
        headers=headers,
    )
    assert game.status_code == 200, game.text
    game_id = game.json()["id"]
    guest = _auth(client, "Riley")
    joined = client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers=_headers(guest["access_token"]),
    )
    assert joined.status_code == 200
    roles = client.post(
        f"/v1/games/{game_id}/roles",
        json={"mode": "manual", "assignments": {
            host["user"]["id"]: "hider",
            guest["user"]["id"]: "seeker",
        }},
        headers=headers,
    )
    assert roles.status_code == 200
    started = client.post(f"/v1/games/{game_id}/start", headers=headers)
    assert started.status_code == 200, started.text
    ended = client.post(f"/v1/games/{game_id}/end", headers=headers)
    assert ended.status_code == 200
    assert ended.json()["phase"] == "ended"
    return {
        "id": game_id,
        "headers": headers,
        "guest": guest,
        "join_code": game.json()["join_code"],
    }


def test_rematch_opens_a_new_lobby_with_same_rules(client: TestClient) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    game_id = ended["id"]
    headers = ended["headers"]

    original = client.app.state.manager.sessions[UUID(game_id)]
    original_preset = original.state.preset
    original_arena_name = original.state.arena.name

    rematch = client.post(f"/v1/games/{game_id}/rematch", headers=headers)
    assert rematch.status_code == 200, rematch.text
    body = rematch.json()
    assert body["phase"] == "lobby"
    new_id = body["game_id"]
    assert new_id != game_id
    assert body["you"]["is_host"] is True
    assert len(body["players"]) == 1
    assert body["join_code"] != ended["join_code"]

    # Ended game stays ended and untouched.
    old = client.get(f"/v1/games/{game_id}", headers=headers).json()
    assert old["phase"] == "ended"

    new_session = client.app.state.manager.sessions[UUID(new_id)]
    assert new_session.state.arena.name == original_arena_name
    assert new_session.state.preset["modules"]["head_start"]["duration"] == 15
    assert new_session.state.preset["id"] == original_preset["id"]

    # Guest can join the new lobby with the new code.
    guest_join = client.post(
        "/v1/games/join",
        json={"join_code": body["join_code"]},
        headers=_headers(ended["guest"]["access_token"]),
    )
    assert guest_join.status_code == 200
    assert guest_join.json()["id"] == new_id


def test_rematch_rejects_live_games(client: TestClient) -> None:
    host = _auth(client, "Casey")
    headers = _headers(host["access_token"])
    arena = client.post(
        "/v1/arenas",
        json=arena_to_dict(square()),
        headers=headers,
    )
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic"},
        headers=headers,
    )
    game_id = game.json()["id"]
    live = client.post(f"/v1/games/{game_id}/rematch", headers=headers)
    assert live.status_code == 409
    assert live.json()["error"]["code"] == "WRONG_PHASE"


def test_guest_rematch_before_host_returns_rematch_not_ready(client: TestClient) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    denied = client.post(
        f"/v1/games/{ended['id']}/rematch",
        headers=_headers(ended["guest"]["access_token"]),
    )
    assert denied.status_code == 409
    body = denied.json()["error"]
    assert body["code"] == "REMATCH_NOT_READY"
    assert "host" in body["message"].lower()


def test_guest_rematch_joins_host_lobby(client: TestClient) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    game_id = ended["id"]
    host_rematch = client.post(
        f"/v1/games/{game_id}/rematch",
        headers=ended["headers"],
    )
    assert host_rematch.status_code == 200, host_rematch.text
    new_id = host_rematch.json()["game_id"]

    guest_rematch = client.post(
        f"/v1/games/{game_id}/rematch",
        headers=_headers(ended["guest"]["access_token"]),
    )
    assert guest_rematch.status_code == 200, guest_rematch.text
    body = guest_rematch.json()
    assert body["game_id"] == new_id
    assert body["phase"] == "lobby"
    assert body["you"]["is_host"] is False
    names = {p["display_name"] for p in body["players"]}
    assert "Casey" in names and "Riley" in names
