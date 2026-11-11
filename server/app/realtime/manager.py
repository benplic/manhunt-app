"""In-memory GameSession map. One tick loop; engine calls stay synchronous."""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from collections.abc import Awaitable, Callable
from datetime import timedelta
from typing import Any
from uuid import UUID

from fastapi import WebSocket

from app.engine.arena import arena_from_dict
from app.engine.clock import Clock
from app.engine.qr import make_qr_token, token_ttl
from app.engine.session import GameSession
from app.engine.uwb import select_uwb_peers
from app.engine.views import build_view
from app.errors import GameRuleError
from app.realtime.clock import WallClock

LIVE_PHASES = frozenset({"lobby", "head_start", "active", "paused"})

log = logging.getLogger("manhunt.realtime")


class SessionManager:
    def __init__(self, clock: Clock | None = None, qr_key: str = "dev") -> None:
        self.clock = clock or WallClock()
        self.qr_key = qr_key
        self.sessions: dict[UUID, GameSession] = {}
        self.sockets: dict[UUID, dict[UUID, WebSocket]] = defaultdict(dict)
        self._last_push: dict[UUID, float] = {}

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
        return session

    def get(self, game_id: UUID) -> GameSession | None:
        return self.sessions.get(game_id)

    def has_live_games(self) -> bool:
        return any(s.state.phase in LIVE_PHASES for s in self.sessions.values())

    async def keep_replica_awake(self, ping: Callable[[], Awaitable[None]]) -> bool:
        """HTTP ping while a hunt is live so ACA does not treat a quiet WS as idle.

        TODO: verify on a real ACA environment that this keeps minReplicas from
        dropping a replica that still has a lobby or active game.
        """
        if not self.has_live_games():
            return False
        await ping()
        return True

    def attach(self, game_id: UUID, player_id: UUID, ws: WebSocket) -> None:
        self.sockets[game_id][player_id] = ws

    def detach(self, game_id: UUID, player_id: UUID) -> None:
        self.sockets.get(game_id, {}).pop(player_id, None)

    def tick_all(self) -> None:
        for session in list(self.sessions.values()):
            # Lobby is otherwise skipped. A sample lobby still has to count down.
            if session.sample_start_after_s is not None and session.state.phase == "lobby":
                self._advance_sample(session)
                continue
            if session.state.phase in {"ended", "lobby"}:
                continue
            session.tick()
            self._refresh_qr(session)

    def _advance_sample(self, session: GameSession) -> None:
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

    async def push_uwb_peers(self, game_id: UUID) -> None:
        """Send uwb_peers only when the selected set changes. Tokens are not logged."""
        session = self.sessions.get(game_id)
        if session is None:
            return
        session.prune_uwb_ranges()
        selected = select_uwb_peers(session.state.players.values())
        for player_id, ws in list(self.sockets.get(game_id, {}).items()):
            peers = selected.get(player_id, [])
            signature = tuple(sorted(peer["player_id"] + peer["token"] for peer in peers))
            if session.state.uwb_peer_signature.get(player_id) == signature:
                continue
            session.state.uwb_peer_signature[player_id] = signature
            try:
                await ws.send_json(envelope("uwb_peers", {"peers": peers}))
            except Exception:
                log.exception("ws_send_failed game_id=%s player_id=%s", game_id, player_id)
                self.detach(game_id, player_id)

    async def broadcast(self, game_id: UUID) -> None:
        session = self.sessions.get(game_id)
        if session is None:
            return
        events = session.drain_events()
        for player_id, ws in list(self.sockets.get(game_id, {}).items()):
            view = build_view(session, player_id)
            try:
                await ws.send_json({"type": "view", "data": view})
                for event in events:
                    if event.sensitive:
                        continue
                    await ws.send_json(
                        {
                            "type": "event",
                            "data": {
                                "seq": event.seq,
                                "type": event.type,
                                "text": event.text,
                                "tone": event.tone,
                                "at": event.created_at.isoformat() if event.created_at else None,
                                "player_id": str(event.player_id) if event.player_id else None,
                            },
                        }
                    )
                qr = session.state.qr_by_hider.get(player_id)
                player = session.state.players[player_id]
                if qr and player.role == "hider":
                    await ws.send_json(
                        {
                            "type": "qr_token",
                            "data": {"token": qr[0], "expires_at": qr[1].isoformat()},
                        }
                    )
            except Exception:
                log.exception("ws_send_failed game_id=%s player_id=%s", game_id, player_id)
                self.detach(game_id, player_id)

    async def tick_loop(
        self,
        enabled: bool,
        *,
        keep_alive: Callable[[], Awaitable[None]] | None = None,
        persist: Callable[[], Awaitable[None]] | None = None,
    ) -> None:
        if not enabled:
            return
        last_ping = 0.0
        while True:
            await asyncio.sleep(1)
            try:
                self.tick_all()
                if persist is not None:
                    await persist()
                for game_id in list(self.sessions):
                    await self.broadcast(game_id)
                now = time.monotonic()
                if keep_alive is not None and now - last_ping >= 15:
                    last_ping = now
                    await self.keep_replica_awake(keep_alive)
            except Exception:
                log.exception("tick_loop_failed")


def envelope(type: str, data: dict[str, Any]) -> dict[str, Any]:
    return {"type": type, "data": data}


# Silence unused import; token TTL is 30s as specified.
_ = timedelta
