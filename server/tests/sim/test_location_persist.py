"""Location messages stage state in memory; the once-per-second persist writes it.

A crash can therefore lose at most the fixes since the last persist (about one second).
Anything older is in `games.inputs` and `game_events` and survives a restart.
"""

from __future__ import annotations

import asyncio
import sqlite3
from pathlib import Path
from uuid import UUID

from fastapi.testclient import TestClient

from app.engine.geo import GeoPoint
from tests.conftest import make_test_app
from tests.engine.helpers import meters
from tests.persist_helpers import persist_like_the_tick
from tests.sim.test_full_games import _open_game


def _fix(ws, point: GeoPoint) -> None:
    ws.send_json(
        {
            "type": "location",
            "data": {"lat": point.lat, "lon": point.lon, "accuracy_m": 5, "flag": "normal"},
        }
    )
    # Ping/pong makes sure the server handled the fix before the test looks at state.
    ws.send_json({"type": "ping", "data": {}})
    assert ws.receive_json()["type"] == "pong"


def _hello(ws, token: str, last_seq: int | None = None) -> None:
    ws.send_json({"type": "hello", "data": {"token": token, "last_seq": last_seq}})
    assert ws.receive_json()["type"] == "welcome"
    assert ws.receive_json()["type"] == "view"


def _sensitive_rows(tmp_path: Path) -> int:
    conn = sqlite3.connect(tmp_path / "manhunt.db")
    try:
        return conn.execute("select count(*) from game_events where sensitive = 1").fetchone()[0]
    finally:
        conn.close()


def test_a_location_message_does_not_touch_the_database(tmp_path: Path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])
            for step in range(3):
                client.app.state.manager.clock.advance(1)
                _fix(ws, meters(40 + step, 40))
            assert _sensitive_rows(tmp_path) == 0

            persist_like_the_tick(client, ws, gid)
            assert _sensitive_rows(tmp_path) >= 1


def test_a_crash_keeps_persisted_fixes_and_loses_only_the_unpersisted_tail(
    tmp_path: Path,
) -> None:
    app = make_test_app(tmp_path)
    saved_point, tail_point = meters(40, 40), meters(60, 60)
    with TestClient(app) as client:
        gid, _host, hider, _seeker, hider_id, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])
            _fix(ws, saved_point)
            persist_like_the_tick(client, ws, gid)
            client.app.state.manager.clock.advance(1)
            _fix(ws, tail_point)

            # A crash never gets to flush: make the shutdown write fail like a dead process.
            async def crashed(*_args, **_kwargs) -> None:
                raise RuntimeError("process died before the next tick")

            client.app.state.game_service.persist_game = crashed

    restarted = make_test_app(tmp_path)
    with TestClient(restarted):
        rebuilt = restarted.state.manager.sessions[UUID(gid)]
        location = rebuilt.state.players[UUID(hider_id)].last_precise
        assert location is not None
        assert (location.lat, location.lon) == (saved_point.lat, saved_point.lon)


def test_a_clean_shutdown_flushes_the_unpersisted_tail(tmp_path: Path) -> None:
    app = make_test_app(tmp_path)
    tail_point = meters(60, 60)
    with TestClient(app) as client:
        gid, _host, hider, _seeker, hider_id, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])
            _fix(ws, tail_point)

    restarted = make_test_app(tmp_path)
    with TestClient(restarted):
        rebuilt = restarted.state.manager.sessions[UUID(gid)]
        location = rebuilt.state.players[UUID(hider_id)].last_precise
        assert location is not None
        assert (location.lat, location.lon) == (tail_point.lat, tail_point.lon)


def test_reconnect_catch_up_replays_events_missed_while_offline(tmp_path: Path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        session = client.app.state.manager.sessions[UUID(gid)]

        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])
        last_seen = session.state.next_seq - 1

        missed = [session.emit("note", {"text": f"missed {index}"}).seq for index in range(3)]

        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"], last_seq=last_seen)
            replayed: list[int] = []
            ws.send_json({"type": "ping", "data": {}})
            while True:
                frame = ws.receive_json()
                if frame["type"] == "pong":
                    break
                if frame["type"] == "event":
                    replayed.append(frame["data"]["seq"])

        assert replayed == missed


def test_an_event_emitted_during_the_replay_arrives_after_it_not_before(
    tmp_path: Path, monkeypatch
) -> None:
    """A live event must never overtake the replay, or clients drop the older events."""
    from app.realtime import ws as ws_module

    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        session = client.app.state.manager.sessions[UUID(gid)]
        last_seen = session.state.next_seq - 1
        missed = [session.emit("note", {"text": f"missed {index}"}).seq for index in range(3)]

        real_visible_to = ws_module.visible_to
        during_replay: list[int] = []

        def visible_and_emit(event, player_id):
            # The first event being replayed triggers a brand new one, as a tick would.
            if not during_replay:
                during_replay.append(session.emit("note", {"text": "during replay"}).seq)
                # And the tick's broadcast runs while the replay is still being sent.
                asyncio.get_running_loop().create_task(
                    client.app.state.manager.broadcast(UUID(gid))
                )
            return real_visible_to(event, player_id)

        monkeypatch.setattr(ws_module, "visible_to", visible_and_emit)

        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"], last_seq=last_seen)
            ws.send_json({"type": "ping", "data": {}})
            seqs: list[int] = []
            while True:
                frame = ws.receive_json()
                if frame["type"] == "pong":
                    break
                if frame["type"] == "event":
                    seqs.append(frame["data"]["seq"])

        assert seqs == [*missed, *during_replay]
        assert seqs == sorted(seqs)
        assert len(seqs) == len(set(seqs))
