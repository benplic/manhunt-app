"""In-memory GameSession map. One tick loop; engine calls stay synchronous."""

from __future__ import annotations

import asyncio
import logging
import time
import weakref
from collections import defaultdict
from collections.abc import Awaitable, Callable
from datetime import timedelta
from typing import Any
from uuid import UUID

from fastapi import WebSocket

from app.demo.bots import BotDriver
from app.engine.arena import arena_from_dict
from app.engine.clock import Clock
from app.engine.events import GameEvent, visible_to
from app.engine.qr import make_qr_token, token_ttl
from app.engine.session import GameSession
from app.engine.views import build_view
from app.errors import GameRuleError
from app.playtest_log import client_fields, get_playtest_log, safe_exc_message
from app.realtime.clock import WallClock
from app.realtime.outbox import SEND_TIMEOUT_S, ClientOutbox

LIVE_PHASES = frozenset({"lobby", "head_start", "active", "paused"})
# Phases where a hunt is running (or could be) and costs a tick every second.
HUNT_PHASES = frozenset({"head_start", "active", "paused"})

# One tick per second is the game-time contract: one game second is one real second.
TICK_INTERVAL_S = 1.0
# Behind schedule by more than this: tick once, log `tick_lag`, and restart the
# schedule from now instead of catching up in a burst (laptop sleep, VM pause).
# TODO: confirm 5 s against real playtest `tick_lag_ms` data and tune.
TICK_LAG_RESYNC_S = 5.0
# Persist or broadcast slower than this is worth a WARNING and a playtest-log line.
SLOW_IO_WARN_MS = 750.0
# Seconds with no socket and no member message before a hunt is frozen.
# TODO: the user decides the final default; 10 minutes is the placeholder from the plan.
DEFAULT_IDLE_FREEZE_S = 600.0
KEEP_ALIVE_EVERY_S = 15.0
# A detached persist, broadcast or ping that runs longer than this is cancelled.
IO_TIMEOUT_S = 15.0
# Whole-shutdown budget for the final persist. Below the usual 10-30 s container grace period.
SHUTDOWN_FLUSH_TOTAL_S = 10.0
# Warn every N consecutive ticks a game's previous persist/broadcast was still running.
SKIP_WARN_EVERY = 10

log = logging.getLogger("manhunt.realtime")


class SessionManager:
    def __init__(
        self,
        clock: Clock | None = None,
        qr_key: str = "dev",
        *,
        demo_controls_enabled: bool = True,
        idle_freeze_s: float | None = DEFAULT_IDLE_FREEZE_S,
        monotonic: Callable[[], float] = time.monotonic,
        send_timeout_s: float = SEND_TIMEOUT_S,
    ) -> None:
        self.clock = clock or WallClock()
        # Per-socket send bound. Tests shrink it so a stalled socket times out quickly.
        self.send_timeout_s = send_timeout_s
        self.qr_key = qr_key
        self.demo_controls_enabled = demo_controls_enabled
        # None, 0, or a negative value turns the idle freeze off.
        self.idle_freeze_s = idle_freeze_s if idle_freeze_s and idle_freeze_s > 0 else None
        # Wall-clock-free time source for the realtime layer only. The engine never
        # reads it, so replay stays deterministic.
        self._monotonic = monotonic
        self.sessions: dict[UUID, GameSession] = {}
        self.sockets: dict[UUID, dict[UUID, WebSocket]] = defaultdict(dict)
        # One outbound queue per attached socket; see app.realtime.outbox.
        self._outboxes: dict[UUID, dict[UUID, ClientOutbox]] = defaultdict(dict)
        # Sanitized `hello.data.client` per attached socket, added to every ws_* log line.
        self.clients: dict[UUID, dict[UUID, dict[str, str]]] = defaultdict(dict)
        # Sockets the server closed after failed sends. Their receive loop then ends with a
        # normal disconnect, which must not be logged a second time as `client_close`.
        self.server_closed: weakref.WeakSet[WebSocket] = weakref.WeakSet()
        self._closers: set[asyncio.Task[None]] = set()
        self._last_push: dict[UUID, float] = {}
        # game_id -> monotonic time of the last socket event or member message.
        self._last_activity: dict[UUID, float] = {}
        # (kind, game_id | None) -> the one detached task allowed for that slot.
        self._inflight: dict[tuple[str, UUID | None], asyncio.Task[None]] = {}
        self.skipped_io: dict[str, int] = defaultdict(int)
        self._skip_streak: dict[tuple[str, UUID | None], int] = {}
        # game_id -> fingerprint of the last state a persist wrote for an ended game.
        self._persisted: dict[UUID, tuple[int, int]] = {}

    def register(
        self,
        game_id: UUID,
        arena_snapshot: dict,
        preset_snapshot: dict,
        seed: int,
        join_code: str,
    ) -> GameSession:
        session = GameSession(
            game_id=game_id,
            arena=arena_from_dict(arena_snapshot),
            preset=preset_snapshot,
            clock=self.clock,
            seed=seed,
            join_code=join_code,
            qr_signing_key=self.qr_key,
        )
        self.sessions[game_id] = session
        self.note_activity(game_id)
        return session

    def get(self, game_id: UUID) -> GameSession | None:
        return self.sessions.get(game_id)

    def has_live_games(self) -> bool:
        """A frozen hunt is not live: nobody is in it, so it must not hold a replica awake."""
        return any(
            s.state.phase in LIVE_PHASES and not s.idle_frozen for s in self.sessions.values()
        )

    async def keep_replica_awake(self, ping: Callable[[], Awaitable[None]]) -> bool:
        """HTTP ping while a hunt is live so ACA does not treat a quiet WS as idle.

        TODO: verify on a real ACA environment that this keeps minReplicas from
        dropping a replica that still has a lobby or active game.
        """
        if not self.has_live_games():
            return False
        await ping()
        return True

    def attach(
        self,
        game_id: UUID,
        player_id: UUID,
        ws: WebSocket,
        client: dict[str, str] | None = None,
    ) -> None:
        # A reconnect replaces the old socket. Stop the old socket's sender so it cannot
        # keep writing to a dead connection or report a failure for the new one.
        stale = self._outboxes.get(game_id, {}).pop(player_id, None)
        if stale is not None:
            stale.close()
        self.sockets[game_id][player_id] = ws
        if client:
            self.clients[game_id][player_id] = client
        else:
            self.clients.get(game_id, {}).pop(player_id, None)
        self.note_activity(game_id)
        self._wake_if_frozen(game_id)

    def detach(
        self, game_id: UUID, player_id: UUID, ws: WebSocket | None = None
    ) -> WebSocket | None:
        """Remove a player's socket.

        Pass `ws` from a socket's own handler: when the phone has already reconnected, the
        old handler finishing later must not tear down the new connection.
        """
        current = self.sockets.get(game_id, {}).get(player_id)
        if ws is not None and current is not ws:
            return None
        socket = self.sockets.get(game_id, {}).pop(player_id, None)
        outbox = self._outboxes.get(game_id, {}).pop(player_id, None)
        if outbox is not None:
            outbox.close()
        self.clients.get(game_id, {}).pop(player_id, None)
        # The idle clock starts when the last phone leaves, not when the game began.
        self.note_activity(game_id)
        return socket

    def drop_game_sockets(self, game_id: UUID) -> None:
        """Forget every socket of a deleted game and stop their senders."""
        for outbox in self._outboxes.pop(game_id, {}).values():
            outbox.close()
        self.sockets.pop(game_id, None)
        self.clients.pop(game_id, None)

    def client_info(self, game_id: UUID, player_id: UUID) -> dict[str, str] | None:
        return self.clients.get(game_id, {}).get(player_id)

    def note_activity(self, game_id: UUID) -> None:
        """Record that a member did something. Resets the idle-freeze countdown."""
        self._last_activity[game_id] = self._monotonic()

    def _wake_if_frozen(self, game_id: UUID) -> None:
        session = self.sessions.get(game_id)
        if session is None or not session.idle_frozen:
            return
        session.wake_from_idle()
        log.info("session_idle_wake game_id=%s", game_id)
        get_playtest_log().emit(
            "session_idle_wake",
            game_id=game_id,
            join_code=session.state.join_code,
        )

    def _freeze_if_idle(self, session: GameSession) -> bool:
        """Freeze a running hunt nobody is attached to. True when it is frozen."""
        if session.idle_frozen:
            return True
        game_id = session.state.game_id
        if session.state.phase not in HUNT_PHASES or not self.idle_freeze_s:
            return False
        now = self._monotonic()
        if self.sockets.get(game_id):
            self._last_activity[game_id] = now
            return False
        # Sessions rebuilt after a restart bypass register(); start their clock now.
        last = self._last_activity.setdefault(game_id, now)
        idle_for = now - last
        if idle_for < self.idle_freeze_s:
            return False
        session.idle_frozen = True
        log.info("session_idle_freeze game_id=%s idle_s=%.0f", game_id, idle_for)
        get_playtest_log().emit(
            "session_idle_freeze",
            game_id=game_id,
            join_code=session.state.join_code,
            idle_s=round(idle_for),
            phase=session.state.phase,
        )
        return True

    def tick_all(self) -> None:
        for session in list(self.sessions.values()):
            try:
                self._tick_session(session)
            except Exception:
                # One broken game must not stop the other games' clocks this second.
                log.exception("tick_session_failed game_id=%s", session.state.game_id)

    def _tick_session(self, session: GameSession) -> None:
        # Lobby is otherwise skipped. A sample lobby still has to count down.
        if session.sample_start_after_s is not None and session.state.phase == "lobby":
            self._advance_sample(session)
            return
        if session.state.phase in {"ended", "lobby"}:
            return
        if self._freeze_if_idle(session):
            return
        steps = (
            session.demo.speed
            if session.demo is not None and session.state.phase in {"head_start", "active"}
            else 1
        )
        for _ in range(steps):
            if session.state.phase in {"ended", "lobby", "paused"}:
                break
            session.tick()
            if session.demo is not None:
                BotDriver.step(session)
            self._refresh_qr(session)

    def _advance_sample(self, session: GameSession) -> None:
        if session.demo is not None and session.demo.lobby_hold:
            return
        delay = session.sample_start_after_s
        if delay is None:
            return
        session.sample_waited_s += 1
        remaining = delay - session.sample_waited_s
        session.state.lobby_starts_in_s = max(0, remaining)
        if remaining > 0:
            return
        session.sample_start_after_s = None
        session.state.lobby_starts_in_s = None
        try:
            session.start()
        except GameRuleError:
            log.exception("sample_start_failed game_id=%s", session.state.game_id)

    def _refresh_qr(self, session: GameSession) -> None:
        now = session.clock.now()
        for player in session.state.players.values():
            if player.role != "hider" or player.status != "active":
                continue
            current = session.state.qr_by_hider.get(player.player_id)
            if current and current[1] > now:
                continue
            expires = now + token_ttl()
            token = make_qr_token(
                game_id=session.state.game_id,
                hider_id=player.player_id,
                expires_at=expires,
                key=session.qr_signing_key,
            )
            session.state.qr_by_hider[player.player_id] = (token, expires)

    async def broadcast(self, game_id: UUID) -> None:
        """Queue this tick's frames for every attached socket and return at once.

        Each socket has its own sender (see `ClientOutbox`), so a phone that stopped reading
        cannot delay the others. Delivery is asynchronous; `settle` waits for it in tests.
        """
        session = self.sessions.get(game_id)
        if session is None:
            return
        events = session.drain_events()
        # One JSONL write batch per tick for the drained engine timeline.
        get_playtest_log().record_engine_events(
            game_id,
            events,
            join_code=session.state.join_code,
        )
        for player_id, ws in list(self.sockets.get(game_id, {}).items()):
            view = build_view(
                session,
                player_id,
                demo_controls_enabled=self.demo_controls_enabled,
            )
            event_frames = [
                envelope("event", serialize_event(event))
                for event in events
                if visible_to(event, player_id)
            ]
            qr_frame = None
            qr = session.state.qr_by_hider.get(player_id)
            player = session.state.players.get(player_id)
            if qr and player is not None and player.role == "hider":
                qr_frame = envelope(
                    "qr_token",
                    {"token": qr[0], "expires_at": qr[1].isoformat()},
                )
            self._outbox_for(game_id, player_id, ws).post(
                event_frames, envelope("view", view), qr_frame
            )

    def _outbox_for(self, game_id: UUID, player_id: UUID, ws: WebSocket) -> ClientOutbox:
        outboxes = self._outboxes[game_id]
        outbox = outboxes.get(player_id)
        if outbox is not None and outbox.ws is ws:
            return outbox
        if outbox is not None:
            outbox.close()
        outbox = ClientOutbox(
            game_id,
            player_id,
            ws,
            on_failure=self._on_send_failure,
            monotonic=self._monotonic,
            send_timeout_s=self.send_timeout_s,
        )
        outboxes[player_id] = outbox
        return outbox

    def _on_send_failure(self, outbox: ClientOutbox, exc: BaseException, send_ms: float) -> None:
        """Log a failed or timed-out send; detach only after the grace in `ClientOutbox`."""
        game_id, player_id = outbox.game_id, outbox.player_id
        session = self.sessions.get(game_id)
        join_code = session.state.join_code if session is not None else None
        client = self.client_info(game_id, player_id)
        will_detach = outbox.should_detach
        log.warning(
            "ws_send_failed game_id=%s player_id=%s exc_type=%s failures=%d send_ms=%.0f",
            game_id,
            player_id,
            type(exc).__name__,
            outbox.consecutive_failures,
            send_ms,
        )
        get_playtest_log().emit(
            "ws_send_failed",
            game_id=game_id,
            player_id=player_id,
            join_code=join_code,
            exc_type=type(exc).__name__,
            exc_message=safe_exc_message(exc),
            send_ms=round(send_ms),
            consecutive_failures=outbox.consecutive_failures,
            will_detach=will_detach,
            **client_fields(client),
        )
        if not will_detach:
            return
        # Only the socket that failed may be removed; a reconnect may already own the slot.
        if self.detach(game_id, player_id, outbox.ws) is None:
            return
        get_playtest_log().ws_disconnected(
            game_id,
            player_id,
            join_code=join_code,
            reason="send_failed",
            client=client,
            exc=exc,
            send_ms=send_ms,
        )
        # Dropping it from the map is not enough: left open, the phone would keep pinging
        # a socket that no longer receives views. Close it so the client reconnects.
        self.server_closed.add(outbox.ws)
        closer = asyncio.create_task(self._close_quietly(outbox.ws))
        self._closers.add(closer)
        closer.add_done_callback(self._closers.discard)

    async def _close_quietly(self, ws: WebSocket) -> None:
        try:
            await asyncio.wait_for(ws.close(code=1011), timeout=self.send_timeout_s)
        except Exception as exc:
            # The socket is probably already gone; there is nothing more to do for it.
            log.debug("ws_close_failed exc_type=%s", type(exc).__name__)

    async def settle(self, game_id: UUID | None = None, *, timeout: float = 5.0) -> None:
        """Wait for queued frames to be sent. For tests and shutdown, not the tick path."""
        outboxes = (
            self._outboxes.get(game_id, {}).values()
            if game_id is not None
            else [o for per_game in self._outboxes.values() for o in per_game.values()]
        )
        tasks = [o.task for o in outboxes if o.task is not None and o.sending]
        if tasks:
            await asyncio.wait(tasks, timeout=timeout)

    def _spawn_once(
        self,
        kind: str,
        game_id: UUID | None,
        work: Callable[[], Awaitable[None]],
    ) -> bool:
        """Start `work` as a detached task unless the previous one is still running.

        Skip, never queue: a stuck socket or database must not pile up a backlog that
        fires all at once when it recovers. Persist and broadcast are both idempotent
        snapshots, so the next tick's run covers whatever a skipped run would have done.
        """
        key = (kind, game_id)
        running = self._inflight.get(key)
        if running is not None and not running.done():
            self.skipped_io[kind] += 1
            streak = self._skip_streak.get(key, 0) + 1
            self._skip_streak[key] = streak
            log.debug("%s_skipped game_id=%s reason=previous_in_flight", kind, game_id)
            if streak % SKIP_WARN_EVERY == 0:
                # The previous run has not finished for this many ticks in a row.
                log.warning(
                    "%s_stalled game_id=%s consecutive_skips=%d", kind, game_id, streak
                )
                get_playtest_log().emit(
                    f"{kind}_stalled", game_id=game_id, consecutive_skips=streak
                )
            return False
        self._skip_streak.pop(key, None)
        task = asyncio.create_task(self._timed(kind, game_id, work))
        self._inflight[key] = task
        task.add_done_callback(lambda done: self._release(key, done))
        return True

    def _release(self, key: tuple[str, UUID | None], done: asyncio.Task[None]) -> None:
        if self._inflight.get(key) is done:
            del self._inflight[key]

    async def _timed(
        self,
        kind: str,
        game_id: UUID | None,
        work: Callable[[], Awaitable[None]],
    ) -> None:
        """Run detached I/O, log its duration, and keep its errors off the tick loop."""
        started = self._monotonic()
        try:
            # A hung database or socket must not keep this game's slot (and, for persist,
            # its persist lock) forever. wait_for cancels the work on timeout.
            await asyncio.wait_for(work(), timeout=IO_TIMEOUT_S)
        except TimeoutError:
            log.warning("%s_timeout game_id=%s timeout_s=%.0f", kind, game_id, IO_TIMEOUT_S)
            get_playtest_log().emit(f"{kind}_timeout", game_id=game_id, timeout_s=IO_TIMEOUT_S)
            return
        except asyncio.CancelledError:
            raise
        except Exception:
            # TODO: decide whether repeated persist failures should page someone.
            log.exception("%s_failed game_id=%s", kind, game_id)
            return
        took_ms = (self._monotonic() - started) * 1000.0
        log.debug("%s_ms=%.1f game_id=%s", kind, took_ms, game_id)
        if took_ms >= SLOW_IO_WARN_MS:
            log.warning("%s_slow %s_ms=%.0f game_id=%s", kind, kind, took_ms, game_id)
            get_playtest_log().emit(
                f"{kind}_slow", game_id=game_id, **{f"{kind}_ms": round(took_ms)}
            )

    @staticmethod
    def _persist_fingerprint(session: GameSession) -> tuple[int, int]:
        """Changes whenever a new event or input exists that the database may not have."""
        return (session.state.next_seq, len(session.state.inputs))

    def _persist_is_clean(self, game_id: UUID, session: GameSession) -> bool:
        """An ended game that is already saved has nothing left to write.

        Ended sessions stay in memory, so without this every ended game cost a database
        session and a commit every second, and re-sealing its log rewrote the row.
        """
        return (
            session.state.phase == "ended"
            and self._persisted.get(game_id) == self._persist_fingerprint(session)
        )

    async def _persist_and_mark(
        self,
        session: GameSession,
        persist: Callable[[GameSession], Awaitable[None]],
    ) -> None:
        # Take the fingerprint before the write so a change made during it is not
        # mistaken for saved. A failed persist raises here and is retried next tick.
        fingerprint = self._persist_fingerprint(session)
        await persist(session)
        self._persisted[session.state.game_id] = fingerprint

    async def drain_io(self) -> None:
        """Cancel detached persist/broadcast work and wait until it has stopped.

        Call on shutdown, before the database engine is disposed.
        """
        tasks = list(self._inflight.values())
        for per_game in self._outboxes.values():
            for outbox in per_game.values():
                outbox.close()
                if outbox.task is not None:
                    tasks.append(outbox.task)
        tasks.extend(self._closers)
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def flush_all(
        self,
        persist: Callable[[GameSession], Awaitable[None]],
        *,
        per_game_timeout_s: float = IO_TIMEOUT_S,
        total_timeout_s: float = SHUTDOWN_FLUSH_TOTAL_S,
    ) -> int:
        """Write every game that may hold unsaved state, once, with hard time bounds.

        Shutdown only. Location fixes are staged in memory between ticks, so a clean stop
        saves them here. An ended game that is already saved is skipped, and a hung database
        cannot outlast `total_timeout_s`, because a SIGKILL from the orchestrator would lose
        the very data this is trying to save. Returns how many games were written.
        """
        deadline = self._monotonic() + total_timeout_s
        written = 0
        for game_id, session in list(self.sessions.items()):
            if self._persist_is_clean(game_id, session):
                continue
            remaining = deadline - self._monotonic()
            if remaining <= 0:
                log.warning("shutdown_flush_deadline game_id=%s", game_id)
                break
            try:
                await asyncio.wait_for(
                    self._persist_and_mark(session, persist),
                    timeout=min(per_game_timeout_s, remaining),
                )
                written += 1
            except TimeoutError:
                log.warning("shutdown_flush_timeout game_id=%s", game_id)
            except Exception as exc:
                # Type only: a traceback could carry statement parameters (coordinates).
                # TODO: decide whether a failed shutdown flush should page someone.
                log.error(
                    "shutdown_flush_failed game_id=%s exc_type=%s",
                    game_id,
                    type(exc).__name__,
                )
        return written

    def _schedule_io(
        self,
        persist: Callable[[GameSession], Awaitable[None]] | None,
    ) -> None:
        """Hand persist and broadcast to detached tasks, one of each per game."""
        for game_id, session in list(self.sessions.items()):
            if session.idle_frozen:
                continue
            if persist is not None and not self._persist_is_clean(game_id, session):
                self._spawn_once(
                    "persist", game_id, lambda s=session: self._persist_and_mark(s, persist)
                )
            self._spawn_once("broadcast", game_id, lambda g=game_id: self.broadcast(g))

    async def tick_loop(
        self,
        enabled: bool,
        *,
        keep_alive: Callable[[], Awaitable[None]] | None = None,
        persist: Callable[[GameSession], Awaitable[None]] | None = None,
        monotonic: Callable[[], float] | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        max_ticks: int | None = None,
        max_lag_s: float = TICK_LAG_RESYNC_S,
    ) -> None:
        """Tick on a fixed 1 s grid so one game second is one real second.

        Deadlines advance by exactly TICK_INTERVAL_S from the previous deadline, not
        from "now", so the time spent ticking or being scheduled never accumulates.
        Persist, broadcast, and the keep-alive ping run detached and cannot delay it.

        `monotonic`, `sleep`, and `max_ticks` exist so tests drive the loop with a fake
        clock instead of sleeping. Production passes none of them.
        """
        if not enabled:
            return
        clock = monotonic or self._monotonic
        last_ping = clock() - KEEP_ALIVE_EVERY_S
        deadline = clock() + TICK_INTERVAL_S
        ticks = 0
        try:
            while max_ticks is None or ticks < max_ticks:
                delay = deadline - clock()
                if delay > 0:
                    await sleep(delay)
                else:
                    # Catching up a small lag: still let detached I/O tasks run.
                    await asyncio.sleep(0)
                now = clock()
                lag_s = max(0.0, now - deadline)
                ticks += 1
                try:
                    self.tick_all()
                    self._schedule_io(persist)
                    if keep_alive is not None and now - last_ping >= KEEP_ALIVE_EVERY_S:
                        last_ping = now
                        self._spawn_once(
                            "keep_alive", None, lambda: self.keep_replica_awake(keep_alive)
                        )
                except Exception:
                    log.exception("tick_loop_failed")
                if lag_s > max_lag_s:
                    # Skipping the missed seconds is deliberate: after a laptop sleep
                    # the hunt should resume, not fast-forward through minutes of game.
                    log.warning("tick_lag tick_lag_ms=%.0f resync=true", lag_s * 1000.0)
                    get_playtest_log().emit(
                        "tick_lag", tick_lag_ms=round(lag_s * 1000.0), resync=True
                    )
                    deadline = now + TICK_INTERVAL_S
                else:
                    log.debug("tick tick_lag_ms=%.1f", lag_s * 1000.0)
                    deadline += TICK_INTERVAL_S
        except BaseException:
            # Shutdown (CancelledError) must not leave a persist writing to a disposed engine.
            for task in list(self._inflight.values()):
                task.cancel()
            raise


def envelope(type: str, data: dict[str, Any]) -> dict[str, Any]:
    return {"type": type, "data": data}


def serialize_event(event: GameEvent) -> dict[str, Any]:
    return {
        "seq": event.seq,
        "type": event.type,
        "text": event.text,
        "tone": event.tone,
        "at": event.created_at.isoformat() if event.created_at else None,
        "player_id": str(event.player_id) if event.player_id else None,
        "announcement": event.payload.get("announcement"),
        "subject_name": event.payload.get("subject_name"),
    }


# Silence unused import; token TTL is 30s as specified.
_ = timedelta
