"""A second phone joining, or a role change, reaches the other phone without a refresh."""

import json

import anyio
from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str) -> dict:
    response = client.post("/v1/auth/dev", json={"display_name": name})
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _next(ws, timeout: float = 2):
    """Read one JSON frame, and fail the test if the server never sends it.

    Starlette's test socket blocks forever on an empty queue. Waiting inside
    the portal lets the timeout cancel that wait instead of hanging pytest.
    """

    async def receive():
        with anyio.fail_after(timeout):
            message = await ws._send_rx.receive()
        if message["type"] == "websocket.close":
            raise AssertionError(f"socket closed: {message.get('code')}")
        return json.loads(message["text"])

    try:
        return ws.portal.call(receive)
    except TimeoutError:
        raise AssertionError("expected a websocket frame") from None


def _auth(client: TestClient, name: str) -> dict:
    response = client.post("/v1/auth/dev", json={"display_name": name})
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_join_and_roles_push_a_lobby_view(client: TestClient) -> None:
    host = _auth(client, "Casey")
    guest = _auth(client, "Riley")
    arena = client.post(
        "/v1/arenas",
        json=arena_to_dict(square()),
        headers=_hdr(host["access_token"]),
    )
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    game_id = game.json()["id"]

    with client.websocket_connect(f"/v1/games/{game_id}/ws") as host_ws:
        host_ws.send_json({"type": "hello", "data": {"token": host["access_token"]}})
        assert _next(host_ws)["type"] == "welcome"
        opening = _next(host_ws)
        assert opening["type"] == "view"
        assert [player["display_name"] for player in opening["data"]["players"]] == ["Casey"]

        joined = client.post(
            "/v1/games/join",
            json={"join_code": game.json()["join_code"]},
            headers=_hdr(guest["access_token"]),
        )
        assert joined.status_code == 200, joined.text
        pushed = _next(host_ws)
        assert pushed["type"] == "view"
        names = {player["display_name"] for player in pushed["data"]["players"]}
        assert names == {"Casey", "Riley"}

        with client.websocket_connect(f"/v1/games/{game_id}/ws") as guest_ws:
            guest_ws.send_json({"type": "hello", "data": {"token": guest["access_token"]}})
            assert _next(guest_ws)["type"] == "welcome"
            assert _next(guest_ws)["type"] == "view"

            riley_id = next(
                player["player_id"]
                for player in pushed["data"]["players"]
                if player["display_name"] == "Riley"
            )
            casey_id = next(
                player["player_id"]
                for player in pushed["data"]["players"]
                if player["display_name"] == "Casey"
            )
            roles = client.post(
                f"/v1/games/{game_id}/roles",
                json={
                    "mode": "manual",
                    "assignments": {riley_id: "hider", casey_id: "seeker"},
                },
                headers=_hdr(host["access_token"]),
            )
            assert roles.status_code == 200, roles.text
            guest_view = _next(guest_ws)
            assert guest_view["type"] == "view"
            by_name = {
                player["display_name"]: player["role"] for player in guest_view["data"]["players"]
            }
            assert by_name["Riley"] == "hider"
            assert by_name["Casey"] == "seeker"
