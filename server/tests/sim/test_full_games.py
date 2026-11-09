"""Primary integration tests: scripted bots over REST plus a WebSocket hello."""

from datetime import timedelta
from uuid import UUID

from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from app.engine.qr import make_qr_token
from app.engine.state import LocationReading
from tests.engine.helpers import meters, square


def _auth(client: TestClient, name: str) -> dict:
    response = client.post("/v1/auth/dev", json={"display_name": name})
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _open_game(client: TestClient, overrides: dict | None = None):
    host = _auth(client, "Host")
    hider = _auth(client, "Hider")
    seeker = _auth(client, "Seeker")
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
            "overrides": overrides
            or {
                "head_start": {"enabled": True, "duration": 15},
                "signal_loss": {"silence": 15},
                "zone_policy": {"oob_countdown": 5},
                "reveal_fuzzy": {"interval": 60},
            },
        },
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    code = game.json()["join_code"]
    gid = game.json()["id"]
    client.post("/v1/games/join", json={"join_code": code}, headers=_hdr(hider["access_token"]))
    client.post("/v1/games/join", json={"join_code": code}, headers=_hdr(seeker["access_token"]))
    view = client.get(f"/v1/games/{gid}", headers=_hdr(host["access_token"])).json()
    hider_id = next(p["player_id"] for p in view["players"] if p["display_name"] == "Hider")
    seeker_id = next(p["player_id"] for p in view["players"] if p["display_name"] == "Seeker")
    roles = client.post(
        f"/v1/games/{gid}/roles",
        json={"mode": "manual", "assignments": {hider_id: "hider", seeker_id: "seeker"}},
        headers=_hdr(host["access_token"]),
    )
    assert roles.status_code == 200, roles.text
    started = client.post(f"/v1/games/{gid}/start", headers=_hdr(host["access_token"]))
    assert started.status_code == 200, started.text
    return gid, host, hider, seeker, hider_id, seeker_id


def _hello(client: TestClient, gid: str, token: str) -> None:
    with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
        ws.send_json({"type": "hello", "data": {"token": token, "last_seq": None}})
        assert ws.receive_json()["type"] == "welcome"
        assert ws.receive_json()["type"] == "view"


def _put(session, player_id: str, point, clock) -> None:
    session.record_location(
        UUID(player_id),
        LocationReading(
            lat=point.lat,
            lon=point.lon,
            accuracy_m=5,
            recorded_at=clock.now(),
        ),
    )


def _no_hider_exact(view: dict, hider_id: str) -> None:
    pin = next(p for p in view["players"] if p["player_id"] == hider_id)
    loc = pin.get("location")
    if loc is None:
        return
    if pin["status"] == "signal_lost" or view["phase"] == "ended":
        return
    assert loc.get("kind") != "exact"


def test_scenario_a_qr_tag_seekers_win(client: TestClient) -> None:
    gid, host, hider, seeker, hider_id, seeker_id = _open_game(
        client,
        overrides={"head_start": {"enabled": False}, "win": {"condition": "all_caught"}},
    )
    manager = client.app.state.manager
    session = manager.get(UUID(gid))
    assert session is not None
    _hello(client, gid, hider["access_token"])
    _put(session, hider_id, meters(100, 100), session.clock)
    _put(session, seeker_id, meters(100, 101), session.clock)
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=UUID(hider_id),
        expires_at=session.clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    tagged = client.post(
        f"/v1/games/{gid}/tags/qr",
        json={"token": token},
        headers=_hdr(seeker["access_token"]),
    )
    assert tagged.status_code == 200, tagged.text
    view = client.get(f"/v1/games/{gid}", headers=_hdr(seeker["access_token"])).json()
    assert view["result"]["winner"] == "seekers"
    _no_hider_exact(view, hider_id)


def test_scenario_b_hider_oob_eliminated(client: TestClient) -> None:
    gid, host, hider, seeker, hider_id, seeker_id = _open_game(
        client,
        overrides={
            "head_start": {"enabled": False},
            "zone_policy": {"oob_countdown": 5},
            "win": {"condition": "all_caught", "time_limit": 30},
        },
    )
    manager = client.app.state.manager
    session = manager.get(UUID(gid))
    _put(session, hider_id, meters(100, -80), session.clock)
    for _ in range(8):
        manager.tick_all()
    view = client.get(f"/v1/games/{gid}", headers=_hdr(host["access_token"])).json()
    player = next(p for p in view["players"] if p["player_id"] == hider_id)
    assert player["status"] == "eliminated"


def test_scenario_c_silence_safety_banner(client: TestClient) -> None:
    gid, host, hider, seeker, hider_id, seeker_id = _open_game(
        client,
        overrides={"head_start": {"enabled": False}, "signal_loss": {"silence": 15}},
    )
    manager = client.app.state.manager
    session = manager.get(UUID(gid))
    _put(session, hider_id, meters(40, 40), session.clock)
    session.clock.advance(15)
    manager.tick_all()
    view = client.get(f"/v1/games/{gid}", headers=_hdr(seeker["access_token"])).json()
    assert any(b["tone"] == "safety" for b in view["banners"])
    pin = next(p for p in view["players"] if p["player_id"] == hider_id)
    assert pin["status"] == "signal_lost"


def test_scenario_d_seeker_oob_visible_to_hiders(client: TestClient) -> None:
    gid, host, hider, seeker, hider_id, seeker_id = _open_game(
        client, overrides={"head_start": {"enabled": False}}
    )
    manager = client.app.state.manager
    session = manager.get(UUID(gid))
    _put(session, hider_id, meters(100, 100), session.clock)
    _put(session, seeker_id, meters(100, -80), session.clock)
    manager.tick_all()
    view = client.get(f"/v1/games/{gid}", headers=_hdr(hider["access_token"])).json()
    pin = next(p for p in view["players"] if p["player_id"] == seeker_id)
    assert pin["location"] is not None
    _put(session, seeker_id, meters(100, 100), session.clock)
    manager.tick_all()
    view = client.get(f"/v1/games/{gid}", headers=_hdr(hider["access_token"])).json()
    pin = next(p for p in view["players"] if p["player_id"] == seeker_id)
    assert pin["location"] is None
    seeker_view = client.get(f"/v1/games/{gid}", headers=_hdr(seeker["access_token"])).json()
    _no_hider_exact(seeker_view, hider_id)
