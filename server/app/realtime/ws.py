from __future__ import annotations

import math
import time
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.auth.tokens import parse_token
from app.engine.session import movement_too_fast, note_presence
from app.engine.state import LocationReading
from app.errors import ApiError, GameRuleError
from app.realtime.manager import SessionManager, envelope


def bind_ws(manager: SessionManager, get_settings, persist_location=None):
    router = APIRouter()

    @router.websocket("/v1/games/{game_id}/ws")
    async def game_ws(ws: WebSocket, game_id: UUID) -> None:
        await ws.accept()
        settings = get_settings()
        try:
            first = await ws.receive_json()
        except WebSocketDisconnect:
            return
        if first.get("type") != "hello":
            await ws.close(code=4401)
            return
        data = first.get("data") or {}
        try:
            user_id = parse_token(str(data.get("token", "")), settings.manhunt_session_signing_key)
        except ApiError:
            await ws.close(code=4401)
            return
        session = manager.get(game_id)
        if session is None:
            await ws.close(code=4404)
            return
        if user_id not in session.state.players:
            await ws.close(code=4403)
            return
        manager.attach(game_id, user_id, ws)
        await ws.send_json(
            envelope(
                "welcome",
                {"player_id": str(user_id), "server_time": session.clock.now().isoformat()},
            )
        )
        from app.engine.views import build_view

        await ws.send_json(
            envelope(
                "view",
                build_view(
                    session,
                    user_id,
                    demo_controls_enabled=manager.demo_controls_enabled,
                ),
            )
        )
        last_seq = data.get("last_seq")
        if last_seq is not None:
            try:
                last_seq = int(last_seq)
            except (TypeError, ValueError):
                last_seq = 0
            for event in session.state.event_log:
                if event.seq <= last_seq or event.sensitive:
                    continue
                await ws.send_json(
                    envelope(
                        "event",
                        {
                            "seq": event.seq,
                            "type": event.type,
                            "text": event.text,
                            "tone": event.tone,
                            "at": event.created_at.isoformat() if event.created_at else None,
                            "player_id": str(event.player_id) if event.player_id else None,
                        },
                    )
                )
        last_loc = 0.0
        try:
            while True:
                message = await ws.receive_json()
                kind = message.get("type")
                payload = message.get("data") or {}
                if kind == "ping":
                    await ws.send_json(envelope("pong", {}))
                elif kind == "location":
                    if session.demo is not None:
                        continue
                    now = time.monotonic()
                    if now - last_loc < 0.5:
                        continue
                    last_loc = now
                    try:
                        lat = float(payload["lat"])
                        lon = float(payload["lon"])
                        accuracy_m = float(payload["accuracy_m"])
                    except (KeyError, TypeError, ValueError):
                        continue
                    if not (
                        math.isfinite(lat) and math.isfinite(lon) and math.isfinite(accuracy_m)
                    ):
                        continue
                    reading = LocationReading(
                        lat=lat,
                        lon=lon,
                        accuracy_m=accuracy_m,
                        recorded_at=session.clock.now(),
                        battery=payload.get("battery"),
                        flag=str(payload.get("flag", "normal")),
                    )
                    player = session.state.players.get(user_id)
                    if player is not None and movement_too_fast(player, reading):
                        # Keep silence clock fresh; do not move the pin.
                        note_presence(player, reading.recorded_at)
                        await ws.send_json(
                            envelope(
                                "error",
                                {
                                    "code": "VALIDATION_FAILED",
                                    "message": "That move is too fast.",
                                },
                            )
                        )
                        continue
                    try:
                        session.record_location(user_id, reading)
                    except GameRuleError as exc:
                        await ws.send_json(
                            envelope("error", {"code": exc.code.value, "message": exc.message})
                        )
                        continue
                    if persist_location is not None:
                        await persist_location(session)
                    # Views ride the 1 Hz tick_loop. Broadcasting here multiplies
                    # with every phone (~2 Hz × N) and freezes the live MapKit UI.
        except WebSocketDisconnect:
            manager.detach(game_id, user_id)
        except Exception:
            manager.detach(game_id, user_id)
            await ws.close(code=1011)

    return router
