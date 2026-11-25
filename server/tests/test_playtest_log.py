"""Playtest JSONL sink: timeline files without coordinates or tokens."""

from __future__ import annotations

import json
from pathlib import Path
from uuid import uuid4

from app.engine.events import GameEvent
from app.playtest_log import PlaytestLogger, configure_playtest_log, get_playtest_log


def test_playtest_log_writes_game_and_daily_files(tmp_path: Path) -> None:
    logger = configure_playtest_log(tmp_path)
    game_id = uuid4()
    player_id = uuid4()
    logger.emit(
        "player_joined",
        game_id=game_id,
        player_id=player_id,
        join_code="PARK99",
        display_name="Casey",
        lat=40.66,  # must be scrubbed
        token="secret-token",
    )
    game_file = tmp_path / "games" / f"{game_id}.jsonl"
    daily = list((tmp_path / "daily").glob("*.jsonl"))
    assert game_file.is_file()
    assert len(daily) == 1
    record = json.loads(game_file.read_text().strip())
    assert record["event"] == "player_joined"
    assert record["game_id"] == str(game_id)
    assert record["player_id"] == str(player_id)
    assert record["join_code"] == "PARK99"
    assert record["display_name"] == "Casey"
    assert "lat" not in record
    assert "token" not in record
    assert "ts" in record


def test_ws_reconnect_is_distinct_from_first_connect(tmp_path: Path) -> None:
    logger = PlaytestLogger(tmp_path)
    game_id = uuid4()
    player_id = uuid4()
    logger.ws_connected(game_id, player_id, join_code="ABC123")
    logger.ws_disconnected(game_id, player_id, join_code="ABC123", reason="client_close")
    logger.ws_connected(game_id, player_id, join_code="ABC123")
    lines = [
        json.loads(line)
        for line in (tmp_path / "games" / f"{game_id}.jsonl").read_text().splitlines()
    ]
    assert [row["event"] for row in lines] == [
        "ws_connect",
        "ws_disconnect",
        "ws_reconnect",
    ]


def test_engine_events_skip_sensitive_and_land_in_errors_file(tmp_path: Path) -> None:
    logger = configure_playtest_log(tmp_path)
    game_id = uuid4()
    logger.record_engine_events(
        game_id,
        [
            GameEvent(seq=1, type="tag", payload={"text": "tagged"}, sensitive=False),
            GameEvent(
                seq=2,
                type="location",
                payload={"lat": 1.0, "lon": 2.0},
                sensitive=True,
            ),
        ],
        join_code="ZZZZZZ",
    )
    logger.emit("exception", game_id=game_id, where="tick_loop")
    game_lines = (tmp_path / "games" / f"{game_id}.jsonl").read_text().splitlines()
    assert len(game_lines) == 2  # tag + exception; sensitive skipped
    tag = json.loads(game_lines[0])
    assert tag["event"] == "game.tag"
    assert "lat" not in json.dumps(tag)
    errors = [
        json.loads(line) for line in (tmp_path / "errors.jsonl").read_text().splitlines()
    ]
    assert errors[-1]["event"] == "exception"
    # Restore a disabled logger so other tests do not inherit this tmp dir.
    configure_playtest_log("")
    assert get_playtest_log().enabled is False


def test_lone_surrogate_name_does_not_break_the_sink(tmp_path: Path) -> None:
    logger = PlaytestLogger(tmp_path)
    game_id = uuid4()
    logger.emit("player_joined", game_id=game_id, display_name="Bad\ud800Name")
    logger.emit("player_joined", game_id=game_id, display_name="Ryan O\u2019Donnell")
    lines = (tmp_path / "games" / f"{game_id}.jsonl").read_bytes().decode("utf-8").splitlines()
    assert len(lines) == 2
    assert json.loads(lines[0])["display_name"] == "Bad\ud800Name"
    assert json.loads(lines[1])["display_name"] == "Ryan O\u2019Donnell"
