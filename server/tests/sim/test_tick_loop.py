"""Tick loop timing. No test here sleeps for real seconds.

Time is a FakeTime object: `monotonic()` reads it and `sleep(d)` advances it, so the
loop's schedule is fully deterministic. Slow I/O is modeled with asyncio.Event gates
that the test never opens, which is the worst case for a stalled network or disk.
"""

from __future__ import annotations

import asyncio
import logging
from uuid import UUID, uuid4

import pytest

from app.engine.clock import FakeClock
from app.engine.session import GameSession
from app.realtime.manager import SessionManager
from tests.engine.helpers import make_session


class FakeTime:
    """Deterministic monotonic clock plus a sleep that advances it."""

    def __init__(self, session_clock: FakeClock | None = None) -> None:
        self.now = 1000.0
        self.sleeps: list[float] = []
        self._session_clock = session_clock

    def monotonic(self) -> float:
        return self.now

    async def sleep(self, delay: float) -> None:
        self.sleeps.append(delay)
        self.now += delay
        if self._session_clock is not None:
            self._session_clock.advance(delay)
        # Yield so detached persist/broadcast tasks get to run, like a real sleep would.
        await asyncio.sleep(0)

    def jump(self, seconds: float) -> None:
        """Simulate a laptop sleeping or the event loop being starved."""
        self.now += seconds
        if self._session_clock is not None:
            self._session_clock.advance(seconds)


def _hunt(player_count: int = 2) -> tuple[GameSession, FakeClock]:
    session, clock = make_session(
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
    return session, clock


def _manager_with(session: GameSession, fake: FakeTime) -> SessionManager:
    manager = SessionManager(monotonic=fake.monotonic)
    manager.sessions[session.state.game_id] = session
    return manager


def _record_tick_times(manager: SessionManager, fake: FakeTime) -> list[float]:
    times: list[float] = []
    original = manager.tick_all

    def spy() -> None:
        times.append(fake.now)
        original()

    manager.tick_all = spy  # type: ignore[method-assign]
    return times


async def _run(manager: SessionManager, fake: FakeTime, ticks: int, **kwargs) -> None:
    await manager.tick_loop(
        True,
        monotonic=fake.monotonic,
        sleep=fake.sleep,
        max_ticks=ticks,
        **kwargs,
    )
    # Let detached tasks created by the final tick start before assertions run.
    await asyncio.sleep(0)
    await asyncio.sleep(0)


async def test_slow_broadcast_does_not_stretch_game_time() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)
    gate = asyncio.Event()
    broadcasts: list[UUID] = []

    async def stuck_broadcast(game_id: UUID) -> None:
        broadcasts.append(game_id)
        await gate.wait()

    manager.broadcast = stuck_broadcast  # type: ignore[method-assign]

    await _run(manager, fake, 10)

    gaps = [b - a for a, b in zip(times, times[1:], strict=False)]
    assert gaps == pytest.approx([1.0] * 9)
    assert session.state.game_elapsed_s == 10
    # One in flight per game. The rest are skipped, not queued behind it.
    assert broadcasts == [session.state.game_id]


async def test_slow_persist_does_not_delay_the_next_tick() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)
    gate = asyncio.Event()
    persisted: list[UUID] = []

    async def stuck_persist(game: GameSession) -> None:
        persisted.append(game.state.game_id)
        await gate.wait()

    await _run(manager, fake, 10, persist=stuck_persist)

    gaps = [b - a for a, b in zip(times, times[1:], strict=False)]
    assert gaps == pytest.approx([1.0] * 9)
    assert persisted == [session.state.game_id]


async def test_persist_and_broadcast_overlap_instead_of_running_in_series() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    persist_gate = asyncio.Event()
    started: list[str] = []

    async def stuck_persist(game: GameSession) -> None:
        started.append("persist")
        await persist_gate.wait()

    async def broadcast(game_id: UUID) -> None:
        started.append("broadcast")

    manager.broadcast = broadcast  # type: ignore[method-assign]

    await _run(manager, fake, 3, persist=stuck_persist)

    # A stuck persist must not keep the view push from going out.
    assert started.count("broadcast") == 3
    assert started.count("persist") == 1


async def test_in_flight_work_is_released_when_it_finishes() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    calls: list[int] = []

    async def quick_persist(game: GameSession) -> None:
        calls.append(1)

    await _run(manager, fake, 5, persist=quick_persist)

    assert len(calls) == 5


async def test_persist_failure_is_logged_and_does_not_stop_the_loop(
    caplog: pytest.LogCaptureFixture,
) -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)

    async def broken_persist(game: GameSession) -> None:
        raise RuntimeError("db down")

    with caplog.at_level(logging.ERROR, logger="manhunt.realtime"):
        await _run(manager, fake, 3, persist=broken_persist)

    assert session.state.game_elapsed_s == 3
    assert "persist_failed" in caplog.text


async def test_slow_keep_alive_does_not_delay_the_schedule() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)
    gate = asyncio.Event()

    async def stuck_ping() -> None:
        await gate.wait()

    await _run(manager, fake, 20, keep_alive=stuck_ping)

    gaps = [b - a for a, b in zip(times, times[1:], strict=False)]
    assert gaps == pytest.approx([1.0] * 19)


async def test_clock_jump_ticks_once_and_resyncs_instead_of_bursting(
    caplog: pytest.LogCaptureFixture,
) -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)
    original_tick_all = manager.tick_all
    calls = 0

    def tick_then_maybe_stall() -> None:
        nonlocal calls
        calls += 1
        original_tick_all()
        if calls == 3:
            # Laptop lid closed for 5 minutes right after the third tick.
            fake.jump(300.0)

    manager.tick_all = tick_then_maybe_stall  # type: ignore[method-assign]

    with caplog.at_level(logging.WARNING, logger="manhunt.realtime"):
        await _run(manager, fake, 8)

    # 8 ticks for 8 iterations. A catch-up burst would have run ~300 more.
    assert session.state.game_elapsed_s == 8
    gaps = [b - a for a, b in zip(times, times[1:], strict=False)]
    assert gaps[0:2] == pytest.approx([1.0, 1.0])
    # The tick after the stall happens right away, then the schedule resumes at 1 s.
    assert gaps[2] == pytest.approx(300.0)
    assert gaps[3:] == pytest.approx([1.0] * 4)
    assert "tick_lag" in caplog.text


async def test_small_lag_catches_up_without_logging_a_warning(
    caplog: pytest.LogCaptureFixture,
) -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)
    original_tick_all = manager.tick_all
    calls = 0

    def tick_then_stall_briefly() -> None:
        nonlocal calls
        calls += 1
        original_tick_all()
        if calls == 2:
            fake.jump(2.5)

    manager.tick_all = tick_then_stall_briefly  # type: ignore[method-assign]

    with caplog.at_level(logging.WARNING, logger="manhunt.realtime"):
        await _run(manager, fake, 8)

    # 2.5 s behind but under the resync threshold: two quick catch-up ticks, then back
    # on the original 1 s grid, so tick N still lands at start + N seconds.
    relative = [round(t - 1000.0, 3) for t in times]
    assert relative == [1.0, 2.0, 4.5, 4.5, 5.0, 6.0, 7.0, 8.0]
    assert "tick_lag" not in caplog.text


async def test_paused_game_keeps_the_schedule_but_not_game_time() -> None:
    session, clock = _hunt()
    session.pause()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)

    await _run(manager, fake, 5)

    gaps = [b - a for a, b in zip(times, times[1:], strict=False)]
    assert gaps == pytest.approx([1.0] * 4)
    assert session.state.game_elapsed_s == 0


class _SlowSocket:
    """Minimal WebSocket stand-in. One of these never finishes a send."""

    def __init__(self, gate: asyncio.Event | None = None) -> None:
        self.gate = gate
        self.sent = 0

    async def send_json(self, data: dict) -> None:
        if self.gate is not None:
            await self.gate.wait()
        self.sent += 1

    async def close(self, code: int = 1000) -> None:
        return None


async def test_an_ended_game_is_persisted_once_then_left_alone_until_it_changes() -> None:
    session, clock = _hunt()
    session.end("done")
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    persisted: list[int] = []

    async def persist(game: GameSession) -> None:
        persisted.append(len(game.state.inputs))

    await _run(manager, fake, 6, persist=persist)
    # Once to flush, then nothing: ended sessions stay in memory forever, and re-sealing
    # their log every second was a write per ended game per tick.
    assert len(persisted) == 1

    # Anything new (an event, an input such as the rematch-adjacent host action) persists again.
    session.emit("note", {"text": "late event"})
    await _run(manager, fake, 4, persist=persist)
    assert len(persisted) == 2


async def test_a_running_game_is_still_persisted_every_tick() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    calls: list[int] = []

    async def persist(game: GameSession) -> None:
        calls.append(1)

    await _run(manager, fake, 5, persist=persist)
    assert len(calls) == 5


async def test_a_failed_persist_of_an_ended_game_is_retried() -> None:
    session, clock = _hunt()
    session.end("done")
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    attempts = 0

    async def flaky(game: GameSession) -> None:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise RuntimeError("db blip")

    await _run(manager, fake, 5, persist=flaky)
    assert attempts == 2


async def test_shutdown_waits_for_detached_work_to_stop() -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    stopped = asyncio.Event()

    async def hung(game: GameSession) -> None:
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            stopped.set()
            raise

    await _run(manager, fake, 2, persist=hung)
    await manager.drain_io()

    assert stopped.is_set()
    assert manager._inflight == {}


async def test_a_hung_persist_is_cancelled_and_its_slot_is_freed(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    import app.realtime.manager as manager_module

    monkeypatch.setattr(manager_module, "IO_TIMEOUT_S", 0.05)
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    cancelled = asyncio.Event()

    async def hung_persist(game: GameSession) -> None:
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            cancelled.set()
            raise

    with caplog.at_level(logging.WARNING, logger="manhunt.realtime"):
        await _run(manager, fake, 2, persist=hung_persist)
        # A real, sub-second wait: the timeout runs on the event loop's own clock.
        await asyncio.wait_for(cancelled.wait(), timeout=2)
        await asyncio.sleep(0)

    assert "persist_timeout" in caplog.text
    assert ("persist", session.state.game_id) not in manager._inflight


async def test_a_stalled_persist_logs_a_warning_after_ten_consecutive_skips(
    caplog: pytest.LogCaptureFixture,
) -> None:
    session, clock = _hunt()
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    gate = asyncio.Event()

    async def stuck_persist(game: GameSession) -> None:
        await gate.wait()

    with caplog.at_level(logging.WARNING, logger="manhunt.realtime"):
        await _run(manager, fake, 5, persist=stuck_persist)
        assert "persist_stalled" not in caplog.text
        await _run(manager, fake, 8, persist=stuck_persist)

    assert "persist_stalled" in caplog.text
    assert "consecutive_skips=10" in caplog.text


async def test_27_sockets_with_one_stalled_keep_game_time_at_one_second() -> None:
    session, clock = _hunt(player_count=27)
    fake = FakeTime(clock)
    manager = _manager_with(session, fake)
    times = _record_tick_times(manager, fake)
    stalled = asyncio.Event()
    game_id = session.state.game_id
    player_ids = list(session.state.players)
    sockets = [_SlowSocket(stalled if index == 5 else None) for index in range(27)]
    for player_id, socket in zip(player_ids, sockets, strict=True):
        manager.attach(game_id, player_id, socket)  # type: ignore[arg-type]

    async def quick_persist(game: GameSession) -> None:
        return None

    await _run(manager, fake, 60, persist=quick_persist)

    assert session.state.game_elapsed_s == 60
    average_gap = (times[-1] - times[0]) / (len(times) - 1)
    assert average_gap == pytest.approx(1.0)
    assert fake.sleeps == pytest.approx([1.0] * 60)
    assert sockets[0].sent > 0
    # Each socket has its own sender, so the stalled one no longer starves the sockets
    # after it (see test_broadcast_slow_client.py for the full guarantees).
    assert sockets[6].sent > 0
    assert sockets[5].sent == 0
    await manager.drain_io()
