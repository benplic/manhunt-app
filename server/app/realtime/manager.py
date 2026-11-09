"""In-memory GameSession map. One tick loop; engine calls stay synchronous."""

from __future__ import annotations

import asyncio
import logging
from collections import defaultdict
from datetime import timedelta
from typing import Any
from uuid import UUID

from fastapi import WebSocket

from app.engine.arena import arena_from_dict
from app.engine.clock import Clock
from app.engine.qr import make_qr_token, token_ttl
from app.engine.session import GameSession
from app.engine.views import build_view
from app.realtime.clock import WallClock

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

    def attach(self, game_id: UUID, player_id: UUID, ws: WebSocket) -> None:
        self.sockets[game_id][player_id] = ws

    def detach(self, game_id: UUID, player_id: UUID) -> None:
        self.sockets.get(game_id, {}).pop(player_id, None)

    def tick_all(self) -> None:
        for session in list(self.sessions.values()):
            if session.state.phase in {"ended", "lobby"}:
                continue
            session.tick()
            self._refresh_qr(session)

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

    async def tick_loop(self, enabled: bool) -> None:
        if not enabled:
            return
        while True:
            await asyncio.sleep(1)
            try:
                self.tick_all()
                for game_id in list(self.sessions):
                    await self.broadcast(game_id)
            except Exception:
                log.exception("tick_loop_failed")


def envelope(type: str, data: dict[str, Any]) -> dict[str, Any]:
    return {"type": type, "data": data}


# Silence unused import; token TTL is 30s as specified.
_ = timedelta
