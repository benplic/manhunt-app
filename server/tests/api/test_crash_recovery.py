"""Kill the process mid-game and rebuild from games.inputs."""

from uuid import UUID

from fastapi.testclient import TestClient

from app.engine.geo import GeoPoint
from tests.conftest import make_test_app
from tests.engine.helpers import meters
from tests.sim.test_full_games import _hdr, _open_game


def _send_fix(client: TestClient, game_id: str, token: str, point: GeoPoint) -> None:
    with client.websocket_connect(f"/v1/games/{game_id}/ws") as ws:
        ws.send_json({"type": "hello", "data": {"token": token, "last_seq": None}})
        assert ws.receive_json()["type"] == "welcome"
        assert ws.receive_json()["type"] == "view"
        ws.send_json(
            {
                "type": "location",
                "data": {
                    "lat": point.lat,
                    "lon": point.lon,
                    "accuracy_m": 5,
                    "flag": "normal",
                },
            }
        )
        # The server broadcasts a view after a location; wait so persist finishes.
        message = ws.receive_json()
        assert message["type"] in {"view", "event"}


def test_restart_rebuilds_mid_game_phase_roles_points_and_locations(tmp_path) -> None:
    app = make_test_app(tmp_path)
    hider_point = meters(40, 40)
    seeker_point = meters(50, 50)
    with TestClient(app) as client:
        gid, host, hider, seeker, hider_id, seeker_id = _open_game(
            client,
            overrides={
                "head_start": {"enabled": True, "duration": 30},
                "signal_loss": {"silence": 120},
                "reveal_fuzzy": {"interval": 120},
            },
        )
        _send_fix(client, gid, hider["access_token"], hider_point)
        _send_fix(client, gid, seeker["access_token"], seeker_point)
        live = app.state.manager.sessions[UUID(gid)]
        before_phase = live.state.phase
        before_roles = {str(p.player_id): p.role for p in live.state.players.values()}
        before_points = {str(p.player_id): p.points for p in live.state.players.values()}
        before_precise = {
            str(p.player_id): (p.last_precise.lat, p.last_precise.lon)
            for p in live.state.players.values()
            if p.last_precise is not None
        }
        assert before_phase in {"head_start", "active", "paused"}
        assert before_roles[hider_id] == "hider"
        assert before_roles[seeker_id] == "seeker"
        assert hider_id in before_precise
        assert seeker_id in before_precise

    restarted = make_test_app(tmp_path)
    with TestClient(restarted) as client:
        rebuilt = restarted.state.manager.sessions[UUID(gid)]
        assert rebuilt.state.phase == before_phase
        roles = {str(p.player_id): p.role for p in rebuilt.state.players.values()}
        points = {str(p.player_id): p.points for p in rebuilt.state.players.values()}
        precise = {
            str(p.player_id): (p.last_precise.lat, p.last_precise.lon)
            for p in rebuilt.state.players.values()
            if p.last_precise is not None
        }
        assert roles == before_roles
        assert points == before_points
        assert precise == before_precise
        view = client.get(f"/v1/games/{gid}", headers=_hdr(host["access_token"]))
        assert view.status_code == 200
        assert view.json()["phase"] == before_phase
