"""Tests for demo session hooks: synthetic fixes, speed, hold, WS, restart."""

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.engine.state import LocationReading
from app.realtime.manager import SessionManager
from tests.conftest import make_test_app
from tests.engine.helpers import make_session, meters


def test_set_synthetic_location_skips_events_and_inputs() -> None:
    session, clock = make_session()
    bot_id = uuid4()
    session.add_player(bot_id, "Riley Chen", is_host=False)
    session.set_role(bot_id, "hider")
    before_events = len(session.state.event_log)
    before_inputs = len(session.state.inputs)

    point = meters(50, 50)
    session.set_synthetic_location(
        bot_id,
        LocationReading(lat=point.lat, lon=point.lon, accuracy_m=5.0, recorded_at=clock.now()),
    )

    player = session.state.players[bot_id]
    assert player.location is not None
    assert player.location.point == point
    assert player.last_precise is not None
    assert player.last_location_at == clock.now()
    assert len(session.state.event_log) == before_events
    assert len(session.state.inputs) == before_inputs


def test_tick_all_respects_demo_speed_and_lobby_hold() -> None:
    from app.demo.state import DemoState

    session, clock = make_session(overrides={"head_start": {"enabled": True, "duration": 60}})
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Casey", is_host=True)
    session.add_player(seeker, "Riley", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.sample_start_after_s = 30
    session.state.lobby_starts_in_s = 30
    session.demo = DemoState.initial(session, bot_ids=[seeker])

    manager = SessionManager(clock=clock)
    manager.sessions[session.state.game_id] = session

    session.demo.lobby_hold = True
    manager.tick_all()
    assert session.state.phase == "lobby"
    assert session.state.lobby_starts_in_s == 30

    session.demo.lobby_hold = False
    manager.tick_all()
    assert session.state.lobby_starts_in_s == 29

    session.sample_start_after_s = None
    session.state.lobby_starts_in_s = None
    session.start()
    session.demo.speed = 5
    manager.tick_all()
    assert session.state.game_elapsed_s == 5


def test_ws_ignores_human_location_in_demo_game(client: TestClient) -> None:
    auth = client.post("/v1/auth/dev", json={"display_name": "Casey"}).json()
    headers = {"Authorization": f"Bearer {auth['access_token']}"}
    joined = client.post("/v1/games/join", headers=headers, json={"join_code": "PARK42"}).json()
    gid = joined["id"]
    session = client.app.state.manager.get(UUID(gid))
    assert session is not None
    assert session.demo is not None

    client.post(f"/v1/games/{gid}/start", headers=headers)
    host_id = UUID(auth["user"]["id"])
    initial_loc = session.state.players[host_id].location
    assert initial_loc is not None

    with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
        ws.send_json({"type": "hello", "data": {"token": auth["access_token"], "last_seq": None}})
        assert ws.receive_json()["type"] == "welcome"
        assert ws.receive_json()["type"] == "view"
        ws.send_json(
            {
                "type": "location",
                "data": {"lat": 10.0, "lon": 10.0, "accuracy_m": 5, "flag": "normal"},
            }
        )
        ws.send_json({"type": "ping", "data": {}})
        assert ws.receive_json()["type"] == "pong"

    after_loc = session.state.players[host_id].location
    assert after_loc is not None
    assert after_loc.lat == initial_loc.lat
    assert after_loc.lon == initial_loc.lon


def test_restart_marks_sample_game_abandoned_and_allows_new_park42(tmp_path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        auth = client.post("/v1/auth/dev", json={"display_name": "Casey"}).json()
        headers = {"Authorization": f"Bearer {auth['access_token']}"}
        first = client.post("/v1/games/join", headers=headers, json={"join_code": "PARK42"}).json()
        gid = first["id"]
        client.post(f"/v1/games/{gid}/start", headers=headers)

    restarted = make_test_app(tmp_path)
    with TestClient(restarted) as client:
        assert UUID(gid) not in restarted.state.manager.sessions
        auth2 = client.post("/v1/auth/dev", json={"display_name": "Morgan"}).json()
        headers2 = {"Authorization": f"Bearer {auth2['access_token']}"}
        second = client.post("/v1/games/join", headers=headers2, json={"join_code": "PARK42"})
        assert second.status_code == 200
        assert second.json()["id"] != gid
