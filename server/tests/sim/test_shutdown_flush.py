"""The shutdown flush is bounded and skips games that are already saved."""

from __future__ import annotations

import asyncio
import importlib.util
import json
from pathlib import Path
from uuid import uuid4

from app.engine.session import GameSession
from app.realtime.manager import SessionManager
from tests.engine.helpers import make_session
from tests.sim.test_tick_loop import FakeTime


def _running_game() -> GameSession:
    session, _clock = make_session(overrides={"head_start": {"enabled": False}})
    hider, seeker = uuid4(), uuid4()
    session.add_player(hider, "Riley", is_host=True)
    session.add_player(seeker, "Jordan", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    return session


def _manager(*sessions: GameSession) -> SessionManager:
    manager = SessionManager(monotonic=FakeTime().monotonic)
    for session in sessions:
        manager.sessions[session.state.game_id] = session
    return manager


async def test_flush_writes_each_live_game_once() -> None:
    first, second = _running_game(), _running_game()
    manager = _manager(first, second)
    written: list = []

    async def persist(game: GameSession) -> None:
        written.append(game.state.game_id)

    assert await manager.flush_all(persist) == 2
    assert set(written) == {first.state.game_id, second.state.game_id}


async def test_flush_skips_an_ended_game_that_is_already_saved() -> None:
    ended = _running_game()
    ended.end("done")
    live = _running_game()
    manager = _manager(ended, live)
    written: list = []

    async def persist(game: GameSession) -> None:
        written.append(game.state.game_id)

    await manager.flush_all(persist)
    assert written.count(ended.state.game_id) == 1

    written.clear()
    await manager.flush_all(persist)
    assert ended.state.game_id not in written
    assert live.state.game_id in written


async def test_a_hung_database_cannot_block_shutdown() -> None:
    game = _running_game()
    manager = _manager(game)
    cancelled = asyncio.Event()

    async def hung(_game: GameSession) -> None:
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            cancelled.set()
            raise

    started = asyncio.get_running_loop().time()
    written = await manager.flush_all(hung, per_game_timeout_s=0.05, total_timeout_s=1.0)

    assert written == 0
    assert cancelled.is_set()
    assert asyncio.get_running_loop().time() - started < 0.5


async def test_one_failing_game_does_not_stop_the_others() -> None:
    bad, good = _running_game(), _running_game()
    manager = _manager(bad, good)
    written: list = []

    async def persist(game: GameSession) -> None:
        if game is bad:
            raise RuntimeError("boom")
        written.append(game)

    assert await manager.flush_all(persist) == 1
    assert written == [good]


async def test_the_total_budget_stops_the_loop() -> None:
    fake = FakeTime()
    games = [_running_game() for _ in range(3)]
    manager = SessionManager(monotonic=fake.monotonic)
    for game in games:
        manager.sessions[game.state.game_id] = game
    written: list = []

    async def persist(game: GameSession) -> None:
        written.append(game)
        fake.now += 6  # each write "takes" 6 s on the manager's clock

    await manager.flush_all(persist, total_timeout_s=10.0)

    assert len(written) == 2


def _load_script():
    path = Path(__file__).resolve().parents[2] / "scripts" / "ws_disconnects_by_platform.py"
    spec = importlib.util.spec_from_file_location("ws_disconnects_by_platform", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_analysis_script_lists_a_platform_with_no_disconnects(tmp_path: Path) -> None:
    lines = [
        {"ts": "2026-11-24T20:00:00Z", "event": "ws_connect", "player_id": "a", "platform": "ios"},
        {"ts": "2026-11-24T20:00:00Z", "event": "ws_connect", "player_id": "b", "platform": "web"},
        {
            "ts": "2026-11-24T20:05:00Z",
            "event": "ws_disconnect",
            "player_id": "b",
            "platform": "web",
            "reason": "client_close",
            "close_code": 1006,
        },
    ]
    log = tmp_path / "day.jsonl"
    log.write_text("\n".join(json.dumps(line) for line in lines), encoding="utf-8")

    result = _load_script().analyze(log)

    assert result["ios"]["disconnects"] == 0
    assert result["ios"]["per_player_minute"] == 0
    assert result["web"]["disconnects"] == 1
    assert result["web"]["close_codes"] == {"1006": 1}
    assert result["web"]["players"] == 1
