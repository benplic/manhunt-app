"""Test stand-in for the tick loop's once-per-second persist (the loop is off in tests)."""

from __future__ import annotations

from uuid import UUID

from fastapi.testclient import TestClient


def persist_like_the_tick(client: TestClient, ws, game_id: str) -> None:
    """Write the live game to the database the way the next tick would.

    Locations are staged in memory and only written by the tick's persist, so a test that
    reads game_events or restarts the app must run this first.
    """

    async def persist() -> None:
        live = client.app.state.manager.sessions[UUID(game_id)]
        async with client.app.state.session_factory() as db:
            await client.app.state.game_service.persist_game(db, live, commit=True)

    ws.portal.call(persist)
