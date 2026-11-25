"""Every disconnect in the playtest log carries a cause and a client platform."""

from __future__ import annotations

import json
import time
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.playtest_log import configure_playtest_log, safe_exc_message, sanitize_client
from tests.conftest import make_test_app
from tests.sim.test_full_games import _open_game

CLIENT = {"platform": "ios", "app_version": "1.4.2", "os_version": "18.4"}


@pytest.fixture
def log_dir(tmp_path: Path):
    root = tmp_path / "playtest"
    yield root
    # Other tests expect the logger disabled.
    configure_playtest_log("")


def _lines(root: Path, event: str) -> list[dict]:
    daily = list((root / "daily").glob("*.jsonl"))
    records = [
        json.loads(line)
        for path in daily
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    return [record for record in records if record["event"] == event]


def _wait_for(root: Path, event: str, timeout: float = 3.0) -> list[dict]:
    """The handler logs from the server thread, after the test's socket has closed."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = _lines(root, event)
        if found:
            return found
        time.sleep(0.02)
    return _lines(root, event)


def _app(tmp_path: Path, log_dir: Path):
    app = make_test_app(tmp_path)
    configure_playtest_log(log_dir)
    return app


def _hello(ws, token: str, client_block: object = CLIENT) -> None:
    data: dict = {"token": token, "last_seq": None}
    if client_block is not None:
        data["client"] = client_block
    ws.send_json({"type": "hello", "data": data})
    assert ws.receive_json()["type"] == "welcome"
    assert ws.receive_json()["type"] == "view"


def test_hello_client_is_echoed_on_ws_connect(tmp_path: Path, log_dir: Path) -> None:
    with TestClient(_app(tmp_path, log_dir)) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])

    connect = _wait_for(log_dir, "ws_connect")[0]
    assert connect["platform"] == "ios"
    assert connect["app_version"] == "1.4.2"
    assert connect["os_version"] == "18.4"


def test_old_builds_without_client_still_connect(tmp_path: Path, log_dir: Path) -> None:
    with TestClient(_app(tmp_path, log_dir)) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"], client_block=None)

    connect = _wait_for(log_dir, "ws_connect")[0]
    assert "platform" not in connect


@pytest.mark.parametrize("bad", ["ios", 7, ["web"], {"platform": "Windows Phone 7"}])
def test_malformed_client_values_never_break_the_socket(
    tmp_path: Path, log_dir: Path, bad: object
) -> None:
    with TestClient(_app(tmp_path, log_dir)) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"], client_block=bad)

    connect = _wait_for(log_dir, "ws_connect")[0]
    assert connect.get("platform", "other") == "other"


def test_client_close_logs_close_code_and_platform(tmp_path: Path, log_dir: Path) -> None:
    with TestClient(_app(tmp_path, log_dir)) as client:
        gid, _host, hider, _seeker, _hid, _sid = _open_game(client)
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])

    disconnect = _wait_for(log_dir, "ws_disconnect")[0]
    assert disconnect["reason"] == "client_close"
    assert disconnect["exc_type"] == "WebSocketDisconnect"
    assert isinstance(disconnect["close_code"], int)
    assert disconnect["platform"] == "ios"


def test_forced_server_error_logs_exception_type_and_close_code(
    tmp_path: Path, log_dir: Path
) -> None:
    with TestClient(_app(tmp_path, log_dir)) as client:
        gid, _host, hider, _seeker, hider_id, _sid = _open_game(client)
        session = client.app.state.manager.sessions[UUID(gid)]

        def explode(*_args, **_kwargs):
            # Coordinates and a token-like blob in the message must not reach the log.
            raise RuntimeError("boom at 40.123456 with " + "A" * 40)

        session.record_location = explode  # type: ignore[method-assign]
        with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
            _hello(ws, hider["access_token"])
            ws.send_json(
                {
                    "type": "location",
                    "data": {"lat": 40.0, "lon": -75.0, "accuracy_m": 5, "flag": "normal"},
                }
            )
            _wait_for(log_dir, "exception")

    exception = _wait_for(log_dir, "exception")[0]
    assert exception["exc_type"] == "RuntimeError"
    assert exception["close_code"] == 1011
    assert exception["platform"] == "ios"
    assert "40.123456" not in exception["exc_message"]
    assert "A" * 40 not in exception["exc_message"]

    disconnect = _wait_for(log_dir, "ws_disconnect")[0]
    assert disconnect["reason"] == "server_error"
    assert disconnect["exc_type"] == "RuntimeError"
    assert disconnect["close_code"] == 1011


def test_sanitize_client_edge_cases() -> None:
    assert sanitize_client(None) is None
    assert sanitize_client("ios") is None
    assert sanitize_client({}) == {"platform": "other", "app_version": "", "os_version": ""}
    long = sanitize_client({"platform": "WEB", "app_version": "x" * 500, "os_version": "1\n2"})
    assert long is not None
    assert long["platform"] == "web"
    assert len(long["app_version"]) == 32
    assert long["os_version"] == "12"


def test_safe_exc_message_truncates_and_redacts() -> None:
    assert safe_exc_message(None) is None
    assert safe_exc_message(ValueError("")) == ""
    assert len(safe_exc_message("x " * 500) or "") == 200
    assert safe_exc_message("at 40.661600, -73.968800") == "at <num>, <num>"
