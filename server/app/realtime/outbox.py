"""Per-socket outbound queue: one slow phone must never delay anyone else.

The tick loop used to await every socket in turn, so a single phone that stopped reading
starved every player after it and stretched the whole broadcast. Each socket now owns a
tiny outbox with its own sender task:

- Events are never dropped or reordered. They are small, and the client keys its
  `last_seq` replay off them.
- The view and the QR token are snapshots, so the newest one wins. If a send is still in
  flight when the next tick has a fresher view, the older pending view is replaced instead
  of queued. A slow phone therefore sees the latest state when it catches up, not a backlog.
- Every send is bounded by `SEND_TIMEOUT_S`. A timeout or error counts as one failure; a
  success clears the count. Detaching on the first failure made every Wi-Fi hiccup a
  reconnect, so the owner (the manager) only detaches once `should_detach` says the
  failures are consecutive or have lasted `FAILURE_GRACE_S`.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable
from typing import Any
from uuid import UUID

from fastapi import WebSocket

log = logging.getLogger("manhunt.realtime")

# TODO: tune after measuring `send_ms` on real playtest logs; 3 s is the plan's suggestion.
SEND_TIMEOUT_S = 3.0
# Detach after this many failed sends in a row...
MAX_CONSECUTIVE_FAILURES = 2
# ...or once the first failure of the current run is this old, whichever comes first.
FAILURE_GRACE_S = 5.0

# (kind, frame). Kind lets a failed send put events back and drop stale snapshots.
_Frame = tuple[str, dict[str, Any]]

FailureHook = Callable[["ClientOutbox", BaseException, float], None]


class ClientOutbox:
    """Outbound frames for one attached socket, drained by its own task."""

    def __init__(
        self,
        game_id: UUID,
        player_id: UUID,
        ws: WebSocket,
        *,
        on_failure: FailureHook,
        monotonic: Callable[[], float] = time.monotonic,
        send_timeout_s: float = SEND_TIMEOUT_S,
    ) -> None:
        self.game_id = game_id
        self.player_id = player_id
        self.ws = ws
        self._on_failure = on_failure
        self._monotonic = monotonic
        self._send_timeout_s = send_timeout_s
        self._events: list[dict[str, Any]] = []
        self._view: dict[str, Any] | None = None
        self._qr: dict[str, Any] | None = None
        self._task: asyncio.Task[None] | None = None
        self._closed = False
        self.consecutive_failures = 0
        self._first_failure_at: float | None = None
        # How long the most recent send took, for the playtest log.
        self.last_send_ms: float | None = None
        # Views replaced before they were ever sent (a slow client skipping ahead).
        self.replaced_views = 0

    @property
    def sending(self) -> bool:
        return self._task is not None and not self._task.done()

    @property
    def task(self) -> asyncio.Task[None] | None:
        return self._task

    @property
    def should_detach(self) -> bool:
        if self.consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
            return True
        if self._first_failure_at is None:
            return False
        return self._monotonic() - self._first_failure_at >= FAILURE_GRACE_S

    def post(
        self,
        events: list[dict[str, Any]],
        view: dict[str, Any] | None,
        qr: dict[str, Any] | None,
    ) -> None:
        """Queue frames and make sure the sender is running. Never blocks."""
        if self._closed:
            return
        self._events.extend(events)
        if view is not None:
            if self._view is not None:
                self.replaced_views += 1
            self._view = view
        if qr is not None:
            self._qr = qr
        self._ensure_running()

    def close(self) -> None:
        """Stop sending for good. Called on detach, replace, and shutdown."""
        self._closed = True
        self._events.clear()
        self._view = None
        self._qr = None
        # The failure hook runs inside the sender and may close its own outbox; a task
        # must not cancel itself, it simply returns right after the hook.
        if (
            self._task is not None
            and not self._task.done()
            and self._task is not asyncio.current_task()
        ):
            self._task.cancel()

    def _ensure_running(self) -> None:
        if self._task is not None and not self._task.done():
            return
        if not (self._events or self._view or self._qr):
            return
        self._task = asyncio.create_task(self._run())

    def _take(self) -> list[_Frame]:
        frames: list[_Frame] = [("event", frame) for frame in self._events]
        if self._view is not None:
            frames.append(("view", self._view))
        if self._qr is not None:
            frames.append(("qr", self._qr))
        self._events = []
        self._view = None
        self._qr = None
        return frames

    def _requeue(self, frames: list[_Frame]) -> None:
        """Put unsent frames back. A snapshot is only restored if nothing newer arrived."""
        unsent_events = [frame for kind, frame in frames if kind == "event"]
        self._events = unsent_events + self._events
        for kind, frame in frames:
            if kind == "view" and self._view is None:
                self._view = frame
            elif kind == "qr" and self._qr is None:
                self._qr = frame

    async def _run(self) -> None:
        while not self._closed:
            frames = self._take()
            if not frames:
                return
            for index, (_kind, frame) in enumerate(frames):
                started = self._monotonic()
                try:
                    await asyncio.wait_for(self.ws.send_json(frame), timeout=self._send_timeout_s)
                except asyncio.CancelledError:
                    raise
                except Exception as exc:
                    # TimeoutError (stalled phone) and send errors (dead socket) are both
                    # one failure; the hook logs and decides whether to detach.
                    send_ms = (self._monotonic() - started) * 1000.0
                    self.last_send_ms = send_ms
                    if self._closed:
                        return
                    self._requeue(frames[index:])
                    self._record_failure()
                    self._on_failure(self, exc, send_ms)
                    # Stop for this round. The next broadcast restarts the sender, which
                    # spaces retries one tick apart instead of hammering a stalled socket.
                    return
                self.last_send_ms = (self._monotonic() - started) * 1000.0
                self.consecutive_failures = 0
                self._first_failure_at = None

    def _record_failure(self) -> None:
        self.consecutive_failures += 1
        if self._first_failure_at is None:
            self._first_failure_at = self._monotonic()
