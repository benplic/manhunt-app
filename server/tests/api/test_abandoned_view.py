"""Abandoned hunts must not rejoin as a fake lobby."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from uuid import UUID

from fastapi.testclient import TestClient

from app.db.models import GameRow
from tests.conftest import make_test_app


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_get_abandoned_game_returns_not_found(tmp_path) -> None:
    app = make_test_app(tmp_path)
    with TestClient(app) as client:
        auth = client.post(
            "/v1/auth/dev",
            json={"display_name": "Casey", "installation_id": "phone-abandon-view", "age": 18},
        )
        assert auth.status_code == 200, auth.text
        token = auth.json()["access_token"]

        arena = client.post(
            "/v1/arenas",
            headers=_headers(token),
            json={
                "name": "Park",
                "boundary": [],
                "boundary_circle": {
                    "center": {"lat": 40.0, "lon": -73.0},
                    "radius_m": 100,
                },
                "zones": [],
            },
        )
        assert arena.status_code == 200, arena.text
        game = client.post(
            "/v1/games",
            headers=_headers(token),
            json={"arena_id": arena.json()["id"], "preset_id": "classic"},
        )
        assert game.status_code == 200, game.text
        game_id = game.json()["id"]

        async def mark_abandoned() -> None:
            async with app.state.session_factory() as session:
                row = await session.get(GameRow, UUID(game_id))
                assert row is not None
                row.status = "abandoned"
                row.ended_at = datetime.now(UTC)
                # Drop the in-memory session so view() cannot serve a live lobby.
                app.state.manager.sessions.pop(UUID(game_id), None)
                await session.commit()

        asyncio.run(mark_abandoned())

        gone = client.get(f"/v1/games/{game_id}", headers=_headers(token))
        assert gone.status_code == 404, gone.text
        assert gone.json()["error"]["code"] == "GAME_NOT_FOUND"
