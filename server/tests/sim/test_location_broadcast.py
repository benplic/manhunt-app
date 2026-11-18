"""Location updates state without an immediate view broadcast; the tick pushes views."""

import json
from uuid import UUID, uuid4

import anyio
from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str) -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4())},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _next(ws, timeout: float = 2):
    async def receive():
        with anyio.fail_after(timeout):
            message = await ws._send_rx.receive()
        if message["type"] == "websocket.close":
            raise AssertionError(f"socket closed: {message.get('code')}")
        return json.loads(message["text"])

    try:
        return ws.portal.call(receive)
    except TimeoutError as exc:
        raise AssertionError("expected a websocket frame") from exc


def _drain_views(ws, limit: int = 20) -> list[dict]:
    """Pull queued frames until a short idle gap; return view payloads only."""
    views: list[dict] = []
    for _ in range(limit):
        try:
            frame = _next(ws, timeout=0.15)
        except AssertionError:
            break
        if frame["type"] == "view":
            views.append(frame["data"])
    return views


def test_location_does_not_push_a_view_until_tick(client: TestClient) -> None:
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
        json={
            "arena_id": arena.json()["id"],
            "preset_id": "classic",
            "overrides": {"head_start": {"enabled": False}},
        },
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    game_id = game.json()["id"]
    client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers=_hdr(guest["access_token"]),
    )
    client.post(
        f"/v1/games/{game_id}/roles",
        json={
            "mode": "manual",
            "assignments": {
                host["user"]["id"]: "hider",
                guest["user"]["id"]: "seeker",
            },
        },
        headers=_hdr(host["access_token"]),
    )
    started = client.post(f"/v1/games/{game_id}/start", headers=_hdr(host["access_token"]))
    assert started.status_code == 200, started.text

    with client.websocket_connect(f"/v1/games/{game_id}/ws") as host_ws:
        host_ws.send_json({"type": "hello", "data": {"token": host["access_token"]}})
        assert _next(host_ws)["type"] == "welcome"
        assert _next(host_ws)["type"] == "view"
        _drain_views(host_ws)

        # Three rapid location reports (server-side throttle is 0.5s; space them).
        for i in range(3):
            host_ws.send_json(
                {
                    "type": "location",
                    "data": {
                        "lat": 40.6616 + i * 0.00001,
                        "lon": -73.9688,
                        "accuracy_m": 5.0,
                        "flag": "normal",
                    },
                }
            )
            # No immediate view after a location. A short wait must not yield one.
            try:
                frame = _next(host_ws, timeout=0.2)
            except AssertionError:
                continue
            assert frame["type"] != "view", (
                "location must not broadcast a view; tick_loop owns view push"
            )

        # Engine state still recorded.
        session = client.app.state.manager.sessions[UUID(game_id)]
        assert session.state.players[UUID(host["user"]["id"])].location is not None