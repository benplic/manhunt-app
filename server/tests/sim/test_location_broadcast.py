"""Location updates state without an immediate view broadcast; the tick pushes views."""

import json
from datetime import timedelta
from uuid import UUID, uuid4

import anyio
from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.engine.state import LocationReading
from app.games.service import GameService
from tests.engine.helpers import meters, square


def _auth(client: TestClient, name: str) -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
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


def _started_two_player_game(
    client: TestClient, overrides: dict | None = None
) -> tuple[dict, dict, str]:
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
            "overrides": overrides or {"head_start": {"enabled": False}},
        },
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    game_id = game.json()["id"]
    joined = client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers=_hdr(guest["access_token"]),
    )
    assert joined.status_code == 200, joined.text
    roles = client.post(
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
    assert roles.status_code == 200, roles.text
    started = client.post(f"/v1/games/{game_id}/start", headers=_hdr(host["access_token"]))
    assert started.status_code == 200, started.text
    return host, guest, game_id


def test_tag_announcement_fields_reach_every_player_live_and_on_reconnect(
    client: TestClient,
) -> None:
    host, guest, game_id = _started_two_player_game(client)
    game_uuid = UUID(game_id)
    hider_id = UUID(host["user"]["id"])
    seeker_id = UUID(guest["user"]["id"])
    manager = client.app.state.manager
    session = manager.sessions[game_uuid]

    with client.websocket_connect(f"/v1/games/{game_id}/ws") as host_ws:
        host_ws.send_json({"type": "hello", "data": {"token": host["access_token"]}})
        assert _next(host_ws)["type"] == "welcome"
        assert _next(host_ws)["type"] == "view"

        with client.websocket_connect(f"/v1/games/{game_id}/ws") as guest_ws:
            guest_ws.send_json({"type": "hello", "data": {"token": guest["access_token"]}})
            assert _next(guest_ws)["type"] == "welcome"
            assert _next(guest_ws)["type"] == "view"

            token = make_qr_token(
                game_id=game_uuid,
                hider_id=hider_id,
                expires_at=session.clock.now() + timedelta(seconds=30),
                key=session.qr_signing_key,
            )
            session.claim_tag(TagClaim(seeker_id, hider_id, qr_token=token))
            tag_event = next(event for event in session.state.event_log if event.type == "tag")
            host_ws.portal.call(manager.broadcast, game_uuid)

            for ws in (host_ws, guest_ws):
                event = _next(ws)
                assert event["type"] == "event"
                assert event["data"] == {
                    "seq": tag_event.seq,
                    "type": "tag",
                    "text": "Riley tagged Casey.",
                    "tone": "success",
                    "at": tag_event.created_at.isoformat(),
                    "player_id": str(hider_id),
                    "announcement": "player_tagged",
                    "subject_name": "Casey",
                }
                pushed = _next(ws)
                while pushed["type"] != "view":
                    pushed = _next(ws)

    with client.websocket_connect(f"/v1/games/{game_id}/ws") as reconnect_ws:
        reconnect_ws.send_json(
            {
                "type": "hello",
                "data": {
                    "token": host["access_token"],
                    "last_seq": tag_event.seq - 1,
                },
            }
        )
        assert _next(reconnect_ws)["type"] == "welcome"
        assert _next(reconnect_ws)["type"] == "view"
        replay = _next(reconnect_ws)
        assert replay["type"] == "event"
        assert replay["data"]["announcement"] == "player_tagged"
        assert replay["data"]["subject_name"] == "Casey"


def test_tick_persist_then_broadcast_delivers_out_of_bounds_announcement(
    client: TestClient,
) -> None:
    host, _guest, game_id = _started_two_player_game(
        client,
        overrides={
            "head_start": {"enabled": False},
            "zone_policy": {"oob_countdown": 5},
        },
    )
    game_uuid = UUID(game_id)
    hider_id = UUID(host["user"]["id"])
    manager = client.app.state.manager
    game = manager.sessions[game_uuid]
    game.record_location(
        hider_id,
        LocationReading(
            lat=meters(300, 100).lat,
            lon=meters(300, 100).lon,
            accuracy_m=5,
            recorded_at=game.clock.now(),
        ),
    )

    with client.websocket_connect(f"/v1/games/{game_id}/ws") as host_ws:
        host_ws.send_json({"type": "hello", "data": {"token": host["access_token"]}})
        assert _next(host_ws)["type"] == "welcome"
        assert _next(host_ws)["type"] == "view"

        for _ in range(7):
            manager.clock.advance(1)
            manager.tick_all()

        async def persist_then_broadcast() -> None:
            service = GameService(manager)
            async with client.app.state.session_factory() as db:
                await service.persist_game(db, game, commit=True)
            await manager.broadcast(game_uuid)

        host_ws.portal.call(persist_then_broadcast)

        event = _next(host_ws)
        assert event["type"] == "event"
        assert event["data"]["announcement"] == "player_tagged_out_of_bounds"
        assert event["data"]["subject_name"] == "Casey"
        assert event["data"]["player_id"] == str(hider_id)
        pushed = _next(host_ws)
        while pushed["type"] != "view":
            pushed = _next(host_ws)
        assert pushed["data"]["phase"] == "ended"


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


def test_reset_flag_moves_a_pin_the_speed_check_would_reject(client: TestClient) -> None:
    """A desk seed can be replaced once. A second reset inside 60s cannot teleport."""
    host = _auth(client, "Casey")
    arena = client.post(
        "/v1/arenas",
        json=arena_to_dict(square()),
        headers=_hdr(host["access_token"]),
    )
    game = client.post(
        "/v1/games",
        json={
            "arena_id": arena.json()["id"],
            "preset_id": "classic",
            "overrides": {"head_start": {"enabled": False}},
        },
        headers=_hdr(host["access_token"]),
    )
    game_id = game.json()["id"]
    guest = _auth(client, "Riley")
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
    clock = client.app.state.manager.clock
    player_id = UUID(host["user"]["id"])

    def pin_lat() -> float:
        session = client.app.state.manager.sessions[UUID(game_id)]
        loc = session.state.players[player_id].location
        assert loc is not None
        return loc.lat

    def send(ws, lat: float, flag: str) -> dict | None:
        # Pace with the game clock. Pump the portal so the handler finishes;
        # send_json alone returns before record_location runs.
        clock.advance(1)
        ws.send_json(
            {
                "type": "location",
                "data": {"lat": lat, "lon": -75.0, "accuracy_m": 12, "flag": flag},
            }
        )
        try:
            frame = _next(ws, timeout=0.4)
        except AssertionError:
            return None
        return frame

    with client.websocket_connect(f"/v1/games/{game_id}/ws") as host_ws:
        host_ws.send_json({"type": "hello", "data": {"token": host["access_token"]}})
        assert _next(host_ws)["type"] == "welcome"
        assert _next(host_ws)["type"] == "view"
        _drain_views(host_ws)

        assert send(host_ws, 40.0, "normal") is None
        assert pin_lat() == 40.0

        error = send(host_ws, 40.01, "normal")
        assert error is not None
        assert error["type"] == "error"
        assert "too fast" in error["data"]["message"].lower()
        assert pin_lat() == 40.0

        assert send(host_ws, 40.01, "reset") is None
        assert pin_lat() == 40.01

        error = send(host_ws, 40.02, "reset")
        assert error is not None
        assert error["type"] == "error"
        assert pin_lat() == 40.01

        clock.advance(60)
        assert send(host_ws, 40.03, "reset") is None
        assert pin_lat() == 40.03