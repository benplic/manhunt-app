import logging
import sqlite3
from uuid import UUID

from fastapi.testclient import TestClient

from app.notify import notifier
from tests.conftest import make_test_app
from tests.engine.helpers import meters
from tests.sim.test_full_games import _hdr, _open_game


def _db(tmp_path):
    return sqlite3.connect(tmp_path / "manhunt.db")


def _send_fix(client: TestClient, game_id: str, token: str, point) -> None:
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
        ws.receive_json()


def test_host_trail_read_writes_audit_without_logging_coordinates(tmp_path, caplog) -> None:
    notifier.sent.clear()
    app = make_test_app(tmp_path)
    point = meters(40, 40)
    with TestClient(app) as client, caplog.at_level(logging.INFO):
        gid, host, hider, seeker, hider_id, _ = _open_game(client)
        _send_fix(client, gid, hider["access_token"], point)
        guest = client.get(f"/v1/games/{gid}/trail", headers=_hdr(hider["access_token"]))
        assert guest.status_code == 403
        trail = client.get(f"/v1/games/{gid}/trail", headers=_hdr(host["access_token"]))
        assert trail.status_code == 200, trail.text
        events = trail.json()["events"]
        assert events
        lats = [e["payload"]["lat"] for e in events if "lat" in e["payload"]]
        assert point.lat in lats
        assert str(point.lat) not in caplog.text
        assert str(point.lon) not in caplog.text
    conn = _db(tmp_path)
    row = conn.execute(
        "select action, detail from audit_log where action = 'trail_read'"
    ).fetchone()
    assert row is not None
    assert row[0] == "trail_read"
    assert row[1] == gid
    assert str(point.lat) not in row[1]


def test_purge_deletes_sensitive_events_older_than_retention(tmp_path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        gid, host, hider, seeker, _, _ = _open_game(client)
        _send_fix(client, gid, hider["access_token"], meters(12, 12))
        conn = _db(tmp_path)
        n = conn.execute("select count(*) from game_events where sensitive = 1").fetchone()[0]
        assert n >= 1
        conn.execute(
            "update game_events set created_at = datetime('now', '-8 days') where sensitive = 1"
        )
        conn.commit()
        conn.close()

    restarted = make_test_app(tmp_path)
    with TestClient(restarted):
        conn = _db(tmp_path)
        left = conn.execute("select count(*) from game_events where sensitive = 1").fetchone()[0]
        assert left == 0


def test_start_and_invite_record_notifications(tmp_path) -> None:
    notifier.sent.clear()
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        gid, host, hider, seeker, hider_id, seeker_id = _open_game(client)
        titles = [n.title for n in notifier.sent]
        assert "Game starting" in titles
        device = client.put(
            "/v1/me/device-token",
            json={"token": "a" * 64},
            headers=_hdr(hider["access_token"]),
        )
        assert device.status_code == 200
        notifier.sent.clear()
        invite = client.get(f"/v1/games/{gid}/invite", headers=_hdr(host["access_token"]))
        assert invite.status_code == 200
        invited = {str(n.user_id) for n in notifier.sent if n.title == "Manhunt invite"}
        assert hider_id in invited
        assert seeker_id in invited
        assert str(UUID(host["user"]["id"])) not in invited or host["user"]["id"] not in invited
