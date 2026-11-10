"""WebSocket discovery-token relay and a tag that ignores a forged range."""

import time
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.engine.state import LocationReading
from tests.engine.helpers import meters
from tests.sim.test_full_games import _hdr, _open_game


def _fix(game, player_id: str, point) -> None:
    game.record_location(
        UUID(player_id),
        LocationReading(
            lat=point.lat,
            lon=point.lon,
            accuracy_m=5,
            recorded_at=game.clock.now(),
        ),
    )


def _hello(ws, token: str) -> None:
    ws.send_json({"type": "hello", "data": {"token": token}})
    assert ws.receive_json()["type"] == "welcome"
    assert ws.receive_json()["type"] == "view"


def _peers(ws, *, want_empty: bool = False) -> list[dict]:
    last = None
    for _ in range(8):
        message = ws.receive_json()
        last = message
        if message.get("type") != "uwb_peers":
            continue
        peers = message["data"]["peers"]
        if want_empty and peers == []:
            return peers
        if not want_empty and peers:
            return peers
    raise AssertionError(last)


def test_relay_tag_ignores_a_forged_range_and_drops_a_non_peer(client: TestClient) -> None:
    gid, _host, hider, seeker, hider_id, seeker_id = _open_game(
        client,
        overrides={
            "head_start": {"enabled": False},
            "tag_policy": {"method": "uwb", "radius_m": 2},
        },
    )
    game = client.app.state.manager.get(UUID(gid))
    assert game is not None
    _fix(game, hider_id, meters(100, 100))
    _fix(game, seeker_id, meters(100, 110))
    seeker_token = "S" * 20
    hider_token = "H" * 20
    with (
        client.websocket_connect(f"/v1/games/{gid}/ws") as seeker_ws,
        client.websocket_connect(f"/v1/games/{gid}/ws") as hider_ws,
    ):
        _hello(seeker_ws, seeker["access_token"])
        _hello(hider_ws, hider["access_token"])
        seeker_ws.send_json({"type": "uwb_token", "data": {"token": seeker_token}})
        hider_ws.send_json({"type": "uwb_token", "data": {"token": hider_token}})
        seeker_peers = _peers(seeker_ws)
        hider_peers = _peers(hider_ws)
        assert seeker_peers[0]["player_id"] == hider_id
        assert seeker_peers[0]["token"] == hider_token
        assert seeker_peers[0]["display_name"] == "Hider"
        assert "lat" not in seeker_peers[0]
        assert hider_peers[0]["player_id"] == seeker_id

        stranger = str(uuid4())
        seeker_ws.send_json(
            {"type": "uwb_range", "data": {"peer_id": stranger, "distance_m": 1}}
        )
        assert UUID(stranger) not in game.state.players[UUID(seeker_id)].uwb_ranges

        # The socket drops a second range inside half a second.
        time.sleep(0.6)
        seeker_ws.send_json(
            {"type": "uwb_range", "data": {"peer_id": hider_id, "distance_m": 1}}
        )
        hider_ws.send_json(
            {"type": "uwb_range", "data": {"peer_id": seeker_id, "distance_m": 1}}
        )

    response = client.post(
        f"/v1/games/{gid}/tags/uwb",
        json={"hider_id": hider_id, "hider_range": 99, "seeker_range": 99},
        headers=_hdr(seeker["access_token"]),
    )
    assert response.status_code == 200, response.text
    assert game.state.players[UUID(hider_id)].status == "eliminated"
