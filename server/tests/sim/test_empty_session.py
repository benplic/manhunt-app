"""Hunts nobody is attached to stop ticking, and a reconnect wakes them.

Idle time is measured on the manager's monotonic clock (a FakeTime here), never the
engine clock, so no test sleeps and the engine stays deterministic.
"""

from __future__ import annotations

import asyncio
import logging
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.engine.recovery import rebuild_session
from app.engine.session import GameSession
from app.engine.state import LocationReading
from app.realtime.manager import SessionManager
from tests.engine.helpers import make_session, meters
from tests.sim.test_full_games import _hello, _open_game
from tests.sim.test_tick_loop import FakeTime, _SlowSocket

IDLE_S = 600.0


def _running_hunt(*, signal_silence: int = 45) -> tuple[GameSession, object, UUID, UUID]:
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "signal_loss": {"enabled": True, "silence": signal_silence},
            "reveal_fuzzy": {"interval": 6000},
        }
    )
    hider, seeker = uuid4(), uuid4()
    session.add_player(hider, "Riley", is_host=True)
    session.add_player(seeker, "Jordan", is_host=False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()
    return session, clock, hider, seeker


def _manager(session: GameSession, fake: FakeTime) -> SessionManager:
    manager = SessionManager(idle_freeze_s=IDLE_S, monotonic=fake.monotonic)
    manager.sessions[session.state.game_id] = session
    manager.note_activity(session.state.game_id)
    return manager


def _fix(session: GameSession, player_id: UUID, clock) -> None:
    point = meters(100, 100)
    session.record_location(
        player_id,
        LocationReading(lat=point.lat, lon=point.lon, accuracy_m=5, recorded_at=clock.now()),
    )


def test_hunt_with_no_sockets_freezes_after_the_idle_time(
    caplog,
) -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)

    for _ in range(5):
        manager.tick_all()
    assert session.state.game_elapsed_s == 5

    fake.now += IDLE_S - 1
    manager.tick_all()
    assert session.idle_frozen is False
    assert session.state.game_elapsed_s == 6

    fake.now += 1
    with caplog.at_level(logging.INFO, logger="manhunt.realtime"):
        manager.tick_all()
    assert session.idle_frozen is True
    assert session.state.game_elapsed_s == 6
    assert "session_idle_freeze" in caplog.text

    for _ in range(50):
        manager.tick_all()
    assert session.state.game_elapsed_s == 6
    assert session.state.phase == "active"


def test_connected_socket_keeps_the_hunt_running_forever() -> None:
    session, _clock, hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)
    manager.attach(session.state.game_id, hider, _SlowSocket())  # type: ignore[arg-type]

    for _ in range(3):
        fake.now += IDLE_S * 5
        manager.tick_all()

    assert session.idle_frozen is False
    assert session.state.game_elapsed_s == 3


def test_member_message_resets_the_idle_countdown() -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)

    fake.now += IDLE_S - 10
    manager.note_activity(session.state.game_id)
    fake.now += IDLE_S - 10
    manager.tick_all()

    assert session.idle_frozen is False


def test_idle_clock_starts_when_the_last_socket_leaves() -> None:
    session, _clock, hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)
    manager.attach(session.state.game_id, hider, _SlowSocket())  # type: ignore[arg-type]

    fake.now += IDLE_S * 3
    manager.tick_all()
    manager.detach(session.state.game_id, hider)

    fake.now += IDLE_S - 1
    manager.tick_all()
    assert session.idle_frozen is False
    fake.now += 1
    manager.tick_all()
    assert session.idle_frozen is True


def test_reconnect_wakes_a_frozen_hunt_and_ticking_resumes(caplog) -> None:
    session, _clock, hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)
    fake.now += IDLE_S
    manager.tick_all()
    assert session.idle_frozen is True

    with caplog.at_level(logging.INFO, logger="manhunt.realtime"):
        manager.attach(session.state.game_id, hider, _SlowSocket())  # type: ignore[arg-type]
    assert session.idle_frozen is False
    assert "session_idle_wake" in caplog.text

    manager.tick_all()
    assert session.state.game_elapsed_s == 1


def test_wake_does_not_flip_everyone_to_signal_lost() -> None:
    session, clock, hider, seeker = _running_hunt(signal_silence=45)
    fake = FakeTime(clock)
    manager = _manager(session, fake)
    _fix(session, hider, clock)
    _fix(session, seeker, clock)

    # Two hours with nobody connected. The engine clock moves with wall time.
    fake.jump(7200)
    manager.tick_all()
    assert session.idle_frozen is True

    manager.attach(session.state.game_id, hider, _SlowSocket())  # type: ignore[arg-type]
    manager.tick_all()

    assert session.state.players[hider].status == "active"
    assert session.state.players[seeker].status == "active"


def test_lobby_and_ended_games_are_never_frozen() -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)
    session.end("done")
    fake.now += IDLE_S * 2
    manager.tick_all()
    assert session.idle_frozen is False

    lobby, _ = make_session()
    manager.sessions[lobby.state.game_id] = lobby
    manager.tick_all()
    assert lobby.idle_frozen is False


def test_zero_idle_time_turns_the_freeze_off() -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = SessionManager(idle_freeze_s=0, monotonic=fake.monotonic)
    manager.sessions[session.state.game_id] = session
    fake.now += 10_000
    manager.tick_all()
    assert session.idle_frozen is False
    assert session.state.game_elapsed_s == 1


def test_rebuilt_session_starts_its_idle_clock_at_first_tick() -> None:
    """A session restored after a restart is not in register(); it still gets a full window."""
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = SessionManager(idle_freeze_s=IDLE_S, monotonic=fake.monotonic)
    manager.sessions[session.state.game_id] = session
    fake.now += 100_000
    manager.tick_all()
    assert session.idle_frozen is False
    fake.now += IDLE_S
    manager.tick_all()
    assert session.idle_frozen is True


def test_wake_input_is_replayed_after_a_crash() -> None:
    session, clock, hider, _seeker = _running_hunt(signal_silence=45)
    _fix(session, hider, clock)
    clock.advance(7200)
    session.idle_frozen = True
    session.wake_from_idle()
    session.tick()
    assert [item["kind"] for item in session.state.inputs][-1] == "idle_wake"

    rebuilt = rebuild_session(
        game_id=session.state.game_id,
        arena=session.state.arena,
        preset=session.state.preset,
        seed=session.state.seed,
        join_code=session.state.join_code,
        inputs=session.state.inputs,
        qr_key=session.qr_signing_key,
    )
    assert rebuilt.state.players[hider].status == "active"
    # The handler itself ran: the silence window was rebased to the wake time, which an
    # unknown or ignored input kind would not do.
    assert rebuilt.state.players[hider].last_location_at == session.clock.now()
    assert rebuilt.state.players[hider].last_location_at == (
        session.state.players[hider].last_location_at
    )


def test_a_frozen_hunt_does_not_count_as_live_or_hold_a_replica_awake() -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)
    assert manager.has_live_games() is True

    fake.now += IDLE_S
    manager.tick_all()

    assert session.idle_frozen is True
    assert manager.has_live_games() is False


def test_one_broken_game_does_not_stop_the_other_games_clocks() -> None:
    broken, _clock, _hider, _seeker = _running_hunt()
    healthy, _clock2, _hider2, _seeker2 = _running_hunt()
    fake = FakeTime()
    manager = SessionManager(idle_freeze_s=IDLE_S, monotonic=fake.monotonic)
    manager.sessions[broken.state.game_id] = broken
    manager.sessions[healthy.state.game_id] = healthy

    def explode() -> None:
        raise RuntimeError("boom")

    broken.tick = explode  # type: ignore[method-assign]
    manager.tick_all()

    assert healthy.state.game_elapsed_s == 1


def test_a_negative_idle_setting_turns_the_freeze_off_instead_of_freezing_at_once() -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = SessionManager(idle_freeze_s=-5, monotonic=fake.monotonic)
    manager.sessions[session.state.game_id] = session
    manager.tick_all()
    assert session.idle_frozen is False
    assert session.state.game_elapsed_s == 1


async def test_tick_loop_skips_persist_and_broadcast_for_frozen_games() -> None:
    session, _clock, _hider, _seeker = _running_hunt()
    fake = FakeTime()
    manager = _manager(session, fake)
    session.idle_frozen = True
    persisted: list[UUID] = []
    broadcasts: list[UUID] = []

    async def persist(game: GameSession) -> None:
        persisted.append(game.state.game_id)

    async def broadcast(game_id: UUID) -> None:
        broadcasts.append(game_id)

    manager.broadcast = broadcast  # type: ignore[method-assign]
    await manager.tick_loop(
        True, persist=persist, monotonic=fake.monotonic, sleep=fake.sleep, max_ticks=3
    )
    await asyncio.sleep(0)

    assert persisted == []
    assert broadcasts == []


def test_smoke_test_game_with_no_phones_stops_ticking(client: TestClient) -> None:
    """A game started over HTTP and then abandoned (like the UXK4HS smoke test) stops."""
    gid, _host, _hider, _seeker, _hider_id, _seeker_id = _open_game(client)
    manager: SessionManager = client.app.state.manager
    session = manager.get(UUID(gid))
    assert session is not None
    fake = FakeTime()
    manager._monotonic = fake.monotonic
    manager.idle_freeze_s = IDLE_S
    manager.note_activity(session.state.game_id)

    manager.tick_all()
    elapsed = session.state.game_elapsed_s
    fake.now += IDLE_S
    manager.tick_all()
    manager.tick_all()

    assert session.idle_frozen is True
    assert session.state.game_elapsed_s == elapsed


def test_real_websocket_connect_wakes_a_frozen_hunt(client: TestClient) -> None:
    gid, _host, hider, _seeker, _hider_id, _seeker_id = _open_game(client)
    manager: SessionManager = client.app.state.manager
    session = manager.get(UUID(gid))
    assert session is not None
    fake = FakeTime()
    manager._monotonic = fake.monotonic
    manager.idle_freeze_s = IDLE_S
    manager.note_activity(session.state.game_id)
    fake.now += IDLE_S
    manager.tick_all()
    assert session.idle_frozen is True

    _hello(client, gid, hider["access_token"])

    assert session.idle_frozen is False
