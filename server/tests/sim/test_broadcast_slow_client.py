"""One slow or dead phone must not delay the others, and must not be dropped too early."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from uuid import UUID, uuid4

from app.engine.session import GameSession
from app.playtest_log import configure_playtest_log
from app.realtime import outbox as outbox_module
from app.realtime.manager import SessionManager
from tests.engine.helpers import make_session
from tests.sim.test_tick_loop import FakeTime


class _Socket:
    """WebSocket stand-in: records frames, and can stall or fail on demand."""

    def __init__(self, *, stall: asyncio.Event | None = None, fail: bool = False) -> None:
        self.stall = stall
        self.fail = fail
        self.frames: list[dict] = []
        self.closed_with: int | None = None

    async def send_json(self, data: dict) -> None:
        if self.fail:
            raise RuntimeError("socket is closed")
        if self.stall is not None:
            await self.stall.wait()
        self.frames.append(data)

    async def close(self, code: int = 1000) -> None:
        self.closed_with = code

    def views(self) -> list[dict]:
        return [frame for frame in self.frames if frame["type"] == "view"]


def _game(player_count: int) -> tuple[GameSession, list[UUID]]:
    session, _clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "signal_loss": {"enabled": False},
            "reveal_fuzzy": {"interval": 600},
        }
    )
    ids = [uuid4() for _ in range(player_count)]
    for index, player_id in enumerate(ids):
        session.add_player(player_id, f"Player {index}", is_host=index == 0)
    session.set_role(ids[0], "hider")
    for player_id in ids[1:]:
        session.set_role(player_id, "seeker")
    session.start()
    return session, ids


def _manager(session: GameSession, fake: FakeTime | None = None) -> SessionManager:
    # Real asyncio timers drive the per-socket timeout, so keep it short in tests.
    manager = SessionManager(monotonic=(fake or FakeTime()).monotonic, send_timeout_s=0.05)
    manager.sessions[session.state.game_id] = session
    return manager


async def test_26_sockets_get_every_view_while_one_never_reads() -> None:
    session, ids = _game(27)
    game_id = session.state.game_id
    manager = _manager(session)
    stalled = asyncio.Event()
    sockets = [_Socket(stall=stalled if index == 13 else None) for index in range(27)]
    for player_id, socket in zip(ids, sockets, strict=True):
        manager.attach(game_id, player_id, socket)  # type: ignore[arg-type]

    ticks = 3
    started = asyncio.get_running_loop().time()
    for _ in range(ticks):
        await manager.broadcast(game_id)
        # broadcast must return without waiting on the stalled socket.
        await asyncio.sleep(0)
    elapsed = asyncio.get_running_loop().time() - started
    await manager.settle(game_id, timeout=0.5)

    healthy = [socket for index, socket in enumerate(sockets) if index != 13]
    assert all(len(socket.views()) == ticks for socket in healthy)
    assert sockets[13].views() == []
    assert elapsed < 0.5
    await manager.drain_io()


async def test_a_pending_view_is_replaced_not_queued_behind_a_slow_send() -> None:
    session, ids = _game(2)
    game_id = session.state.game_id
    manager = _manager(session)
    gate = asyncio.Event()
    slow = _Socket(stall=gate)
    manager.attach(game_id, ids[0], slow)  # type: ignore[arg-type]

    for _ in range(5):
        session.tick()
        await manager.broadcast(game_id)
        await asyncio.sleep(0)

    outbox = manager._outboxes[game_id][ids[0]]
    # View 1 is in flight; views 2-5 queued, and each replaced the previous one.
    assert outbox.replaced_views == 3

    gate.set()
    await manager.settle(game_id, timeout=0.5)
    # The in-flight first view and the single newest pending view. Nothing in between.
    assert len(slow.views()) == 2
    await manager.drain_io()


async def test_events_are_never_dropped_while_views_are_replaced() -> None:
    session, ids = _game(2)
    game_id = session.state.game_id
    manager = _manager(session)
    gate = asyncio.Event()
    slow = _Socket(stall=gate)
    manager.attach(game_id, ids[1], slow)  # type: ignore[arg-type]
    session.drain_events()

    emitted = []
    for index in range(3):
        emitted.append(session.emit("note", {"text": f"note {index}"}).seq)
        await manager.broadcast(game_id)
        await asyncio.sleep(0)
    gate.set()
    await manager.settle(game_id, timeout=0.5)

    delivered = [f["data"]["seq"] for f in slow.frames if f["type"] == "event"]
    assert delivered == emitted
    assert len(slow.views()) < 3
    await manager.drain_io()


async def test_one_failed_send_does_not_detach_a_player() -> None:
    session, ids = _game(2)
    game_id = session.state.game_id
    manager = _manager(session)
    flaky = _Socket(fail=True)
    manager.attach(game_id, ids[0], flaky)  # type: ignore[arg-type]

    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)
    assert manager.sockets[game_id].get(ids[0]) is flaky

    flaky.fail = False
    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)
    assert manager.sockets[game_id].get(ids[0]) is flaky
    assert flaky.views(), "a recovered socket receives views again"
    outbox = manager._outboxes[game_id][ids[0]]
    assert outbox.consecutive_failures == 0
    await manager.drain_io()


async def test_two_consecutive_failures_detach_log_and_close(tmp_path: Path) -> None:
    root = tmp_path / "log"
    configure_playtest_log(root)
    try:
        session, ids = _game(2)
        game_id = session.state.game_id
        manager = _manager(session)
        dead = _Socket(fail=True)
        manager.attach(
            game_id,
            ids[0],
            dead,  # type: ignore[arg-type]
            {"platform": "web", "app_version": "9", "os_version": "Chrome"},
        )

        for _ in range(2):
            await manager.broadcast(game_id)
            await manager.settle(game_id, timeout=0.5)
        await asyncio.sleep(0.05)

        assert ids[0] not in manager.sockets[game_id]
        assert dead.closed_with == 1011
        assert dead in manager.server_closed

        records = [
            json.loads(line)
            for path in (root / "daily").glob("*.jsonl")
            for line in path.read_text(encoding="utf-8").splitlines()
        ]
        disconnect = next(r for r in records if r["event"] == "ws_disconnect")
        assert disconnect["reason"] == "send_failed"
        assert disconnect["exc_type"] == "RuntimeError"
        assert disconnect["platform"] == "web"
        assert "send_ms" in disconnect
        failed = [r for r in records if r["event"] == "ws_send_failed"]
        assert [r["will_detach"] for r in failed] == [False, True]
        await manager.drain_io()
    finally:
        configure_playtest_log("")


async def test_failures_lasting_the_grace_period_detach_on_the_first_retry() -> None:
    session, ids = _game(2)
    game_id = session.state.game_id
    fake = FakeTime()
    manager = _manager(session, fake)
    dead = _Socket(fail=True)
    manager.attach(game_id, ids[0], dead)  # type: ignore[arg-type]

    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)
    assert ids[0] in manager.sockets[game_id]

    fake.now += outbox_module.FAILURE_GRACE_S
    # A single further failure is also the second consecutive one here, so isolate the
    # time rule by checking it directly.
    outbox = manager._outboxes[game_id][ids[0]]
    outbox.consecutive_failures = 1
    assert outbox.should_detach is True
    await manager.drain_io()


async def test_a_stalled_send_times_out_and_the_rest_keep_receiving() -> None:
    session, ids = _game(3)
    game_id = session.state.game_id
    manager = _manager(session)
    stalled = _Socket(stall=asyncio.Event())
    healthy = _Socket()
    manager.attach(game_id, ids[0], stalled)  # type: ignore[arg-type]
    manager.attach(game_id, ids[1], healthy)  # type: ignore[arg-type]

    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)
    await asyncio.sleep(0.1)
    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)
    await asyncio.sleep(0.1)

    assert len(healthy.views()) == 2
    assert ids[0] not in manager.sockets[game_id]
    await manager.drain_io()


async def test_an_old_socket_cannot_detach_its_replacement() -> None:
    session, ids = _game(2)
    game_id = session.state.game_id
    manager = _manager(session)
    old, new = _Socket(), _Socket()
    manager.attach(game_id, ids[0], old)  # type: ignore[arg-type]
    manager.attach(game_id, ids[0], new)  # type: ignore[arg-type]

    assert manager.detach(game_id, ids[0], old) is None  # type: ignore[arg-type]
    assert manager.sockets[game_id][ids[0]] is new

    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)
    assert new.views() and not old.views()
    await manager.drain_io()


async def test_an_old_sockets_failure_does_not_detach_the_reconnected_phone() -> None:
    session, ids = _game(2)
    game_id = session.state.game_id
    manager = _manager(session)
    old = _Socket(fail=True)
    manager.attach(game_id, ids[0], old)  # type: ignore[arg-type]
    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)

    new = _Socket()
    manager.attach(game_id, ids[0], new)  # type: ignore[arg-type]
    await manager.broadcast(game_id)
    await manager.settle(game_id, timeout=0.5)

    assert manager.sockets[game_id][ids[0]] is new
    assert new.views()
    await manager.drain_io()
