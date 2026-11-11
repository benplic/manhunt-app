"""PARK42 is the solo sample lobby: bots, classic rules, a 30s start, then end."""

from uuid import UUID

from fastapi.testclient import TestClient

from app.games.join_code import generate


class _Scripted:
    def __init__(self, chars: str) -> None:
        self.chars = list(chars)

    def choice(self, _alphabet: str) -> str:
        return self.chars.pop(0)


def test_generate_skips_the_sample_code() -> None:
    assert generate(_Scripted("PARK42HUNT42")) == "HUNT42"  # type: ignore[arg-type]


def _auth(client: TestClient, name: str) -> dict:
    return client.post("/v1/auth/dev", json={"display_name": name}).json()


def _headers(auth: dict) -> dict:
    return {"Authorization": f"Bearer {auth['access_token']}"}


def test_park42_fills_bots_starts_and_can_end(client: TestClient) -> None:
    headers = _headers(_auth(client, "Casey"))
    joined = client.post("/v1/games/join", headers=headers, json={"join_code": "PARK42"})
    assert joined.status_code == 200
    game_id = joined.json()["id"]
    view = client.get(f"/v1/games/{game_id}", headers=headers)
    assert view.status_code == 200
    body = view.json()
    assert body["you"]["is_host"] is True
    assert len(body["players"]) == 6
    roles = {player["role"] for player in body["players"]}
    assert "hider" in roles and "seeker" in roles
    assert body["lobby_starts_in_s"] == 30
    assert body["phase"] == "lobby"

    game = client.app.state.manager.sessions[UUID(game_id)]
    assert game.state.preset["id"] == "classic"
    assert game.state.preset["modules"]["roles"]["mode"] == "random"
    assert game.state.arena.name == "Sample park"

    for _ in range(29):
        client.app.state.manager.tick_all()
    mid = client.get(f"/v1/games/{game_id}", headers=headers).json()
    assert mid["phase"] == "lobby"
    assert mid["lobby_starts_in_s"] == 1

    client.app.state.manager.tick_all()
    started = client.get(f"/v1/games/{game_id}", headers=headers).json()
    assert started["phase"] == "head_start"
    assert started["lobby_starts_in_s"] is None

    ended = client.post(f"/v1/games/{game_id}/end", headers=headers)
    assert ended.status_code == 200
    payload = ended.json()
    assert payload["phase"] == "ended"
    assert payload["result"]["reason"]


def test_second_park42_join_reuses_the_lobby(client: TestClient) -> None:
    first = _headers(_auth(client, "Casey"))
    second = _headers(_auth(client, "Morgan"))
    created = client.post("/v1/games/join", headers=first, json={"join_code": "park42"})
    assert created.status_code == 200
    game_id = created.json()["id"]
    again = client.post("/v1/games/join", headers=second, json={"join_code": "PARK42"})
    assert again.status_code == 200
    assert again.json()["id"] == game_id
    view = client.get(f"/v1/games/{game_id}", headers=first).json()
    # The second person joins the same lobby. Bots are not created again.
    assert len(view["players"]) == 7
