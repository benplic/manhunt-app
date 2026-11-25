from __future__ import annotations

import logging
import math
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.auth.tokens import parse_token
from app.engine.events import visible_to
from app.engine.session import consume_location_reset, movement_too_fast, note_presence
from app.engine.state import LocationReading
from app.errors import ApiError, GameRuleError
from app.playtest_log import client_fields, get_playtest_log, safe_exc_message, sanitize_client
from app.realtime.manager import SessionManager, envelope, serialize_event

log = logging.getLogger("manhunt.realtime")


def bind_ws(manager: SessionManager, get_settings):
    """Mount the game socket.

    Locations are staged in memory by `session.record_location` and written by the
    manager's once-per-second persist. A server crash therefore loses the fixes since the
    last successful persist: about one tick normally, longer if the database is slow
    (a persist is abandoned after IO_TIMEOUT_S). `games.inputs` replays everything older,
    and a clean shutdown flushes once more. Committing per fix cost a
    Postgres round trip per phone per message (about 2 Hz x N) on the socket handler.
    """
    router = APIRouter()

    @router.websocket("/v1/games/{game_id}/ws")
    async def game_ws(ws: WebSocket, game_id: UUID) -> None:
        await ws.accept()
        settings = get_settings()
        try:
            first = await ws.receive_json()
        except WebSocketDisconnect:
            return
        except ValueError:
            # Not JSON. The phone never said hello, so there is nothing to detach or log.
            await ws.close(code=4401)
            return
        if not isinstance(first, dict) or first.get("type") != "hello":
            await ws.close(code=4401)
            return
        data = first.get("data") or {}
        if not isinstance(data, dict):
            await ws.close(code=4401)
            return
        # Optional and untrusted: an old app build sends none, and a bad value is ignored.
        client = sanitize_client(data.get("client"))
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

        async def handle_location(payload: dict) -> None:
            if session.demo is not None:
                return
            try:
                lat = float(payload["lat"])
                lon = float(payload["lon"])
                accuracy_m = float(payload["accuracy_m"])
            except (KeyError, TypeError, ValueError):
                return
            if not (
                math.isfinite(lat) and math.isfinite(lon) and math.isfinite(accuracy_m)
            ):
                return
            recorded_at = session.clock.now()
            player = session.state.players.get(user_id)
            # Pace on the game clock so a frozen test clock can space fixes
            # without a wall-clock sleep (that sleep cancels the socket task).
            if (
                player is not None
                and player.last_location_at is not None
                and (recorded_at - player.last_location_at).total_seconds() < 0.5
            ):
                return
            reading = LocationReading(
                lat=lat,
                lon=lon,
                accuracy_m=accuracy_m,
                recorded_at=recorded_at,
                battery=payload.get("battery"),
                flag=str(payload.get("flag", "normal")),
            )
            allow_jump = (
                player is not None
                and reading.flag == "reset"
                and consume_location_reset(player, recorded_at)
            )
            if player is not None and not allow_jump and movement_too_fast(player, reading):
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
                return
            try:
                session.record_location(user_id, reading)
            except GameRuleError as exc:
                await ws.send_json(
                    envelope("error", {"code": exc.code.value, "message": exc.message})
                )
                return
            # Views ride the 1 Hz tick_loop. Broadcasting here multiplies
            # with every phone (~2 Hz × N) and freezes the live MapKit UI.

        try:
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
                    cursor = int(last_seq)
                except (TypeError, ValueError):
                    cursor = 0
            else:
                # No replay requested: start from the current head so only events that land
                # during this handshake are delivered below.
                cursor = session.state.next_seq - 1
            # Catch up until nothing newer exists, and only then attach. Attaching first let
            # a live event from the tick overtake the replay, and clients drop any event whose
            # seq is not newer than the last one seen, so the older replayed events were lost.
            # There is no await between the empty check and `attach`, so an event cannot slip
            # into the gap: it is either in the log (sent here) or emitted after attach
            # (sent by the broadcast).
            while True:
                pending = [event for event in session.state.event_log if event.seq > cursor]
                if not pending:
                    break
                for event in pending:
                    cursor = max(cursor, event.seq)
                    if not visible_to(event, user_id):
                        continue
                    await ws.send_json(envelope("event", serialize_event(event)))
            manager.attach(game_id, user_id, ws, client)
            get_playtest_log().ws_connected(
                game_id,
                user_id,
                join_code=session.state.join_code,
                client=client,
            )
            while True:
                message = await ws.receive_json()
                manager.note_activity(game_id)
                if not isinstance(message, dict):
                    continue
                kind = message.get("type")
                payload = message.get("data") or {}
                if kind == "ping":
                    await ws.send_json(envelope("pong", {}))
                elif kind == "location":
                    await handle_location(payload)
        except WebSocketDisconnect as exc:
            manager.detach(game_id, user_id, ws)
            # A socket the server already closed after failed sends was logged then.
            if ws not in manager.server_closed:
                get_playtest_log().ws_disconnected(
                    game_id,
                    user_id,
                    join_code=session.state.join_code,
                    reason="client_close",
                    client=client,
                    exc=exc,
                    close_code=exc.code,
                )
        except Exception as exc:
            manager.detach(game_id, user_id, ws)
            if ws in manager.server_closed and isinstance(exc, RuntimeError):
                # The outbox already closed this socket and logged why; a RuntimeError is
                # the handler sending on that closed socket, not a second failure. Any other
                # exception type still gets logged below.
                return
            # Type and scrubbed text only: a raw traceback could carry coordinates or tokens.
            log.error(
                "ws_handler_failed game_id=%s player_id=%s exc_type=%s exc_message=%s",
                game_id,
                user_id,
                type(exc).__name__,
                safe_exc_message(exc),
            )
            get_playtest_log().emit(
                "exception",
                game_id=game_id,
                player_id=user_id,
                join_code=session.state.join_code,
                where="game_ws",
                exc_type=type(exc).__name__,
                exc_message=safe_exc_message(exc),
                close_code=1011,
                **client_fields(client),
            )
            get_playtest_log().ws_disconnected(
                game_id,
                user_id,
                join_code=session.state.join_code,
                reason="server_error",
                client=client,
                exc=exc,
                close_code=1011,
            )
            try:
                await ws.close(code=1011)
            except Exception as close_exc:
                # Already closed by the peer or the server; nothing left to close.
                log.debug(
                    "ws_close_after_error_failed game_id=%s exc_type=%s",
                    game_id,
                    type(close_exc).__name__,
                )

    return router
