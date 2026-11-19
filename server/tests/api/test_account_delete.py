"""DELETE /v1/me removes personal data and invalidates refresh tokens."""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.db.models import ArenaRow, GamePlayerRow, User
from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str) -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_delete_me_removes_guest_from_hosts_live_game(client: TestClient) -> None:
    host = _auth(client, "Casey")
    guest = _auth(client, "Riley")
    arena = client.post(
        "/v1/arenas",
        json=arena_to_dict(square()),
        headers={"Authorization": f"Bearer {host['access_token']}"},
    )
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
        headers={"Authorization": f"Bearer {host['access_token']}"},
    )
    assert game.status_code == 200, game.text
    game_id = UUID(game.json()["id"])
    guest_id = UUID(guest["user"]["id"])

    joined = client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers={"Authorization": f"Bearer {guest['access_token']}"},
    )
    assert joined.status_code == 200, joined.text

    manager = client.app.state.manager
    live = manager.get(game_id)
    assert live is not None
    assert guest_id in live.state.players

    deleted = client.delete("/v1/me", headers={"Authorization": f"Bearer {guest['access_token']}"})
    assert deleted.status_code == 200
    assert deleted.json() == {"ok": True}

    async def check_db() -> None:
        async with client.app.state.session_factory() as session:
            assert await session.get(User, guest_id) is None
            assert await session.get(GamePlayerRow, (game_id, guest_id)) is None

    asyncio.run(check_db())

    live_after = manager.get(game_id)
    assert live_after is not None
    assert guest_id not in live_after.state.players


def test_delete_me_removes_user_and_tokens(client: TestClient) -> None:
    user = client.post(
        "/v1/auth/dev",
        json={"display_name": "Casey", "installation_id": str(uuid4()), "age": 20},
    ).json()
    headers = {"Authorization": f"Bearer {user['access_token']}"}
    client.put("/v1/me/device-token", json={"token": "devicetoken-12345678"}, headers=headers)
    gone = client.delete("/v1/me", headers=headers)
    assert gone.status_code == 200
    assert gone.json() == {"ok": True}
    me = client.get("/v1/me", headers=headers)
    assert me.status_code == 401
    refresh = client.post("/v1/auth/refresh", json={"refresh_token": user["refresh_token"]})
    assert refresh.status_code == 401


def test_delete_me_removes_owned_arena(client: TestClient) -> None:
    user = client.post(
        "/v1/auth/dev",
        json={"display_name": "Casey", "installation_id": str(uuid4()), "age": 18},
    ).json()
    headers = {"Authorization": f"Bearer {user['access_token']}"}
    created = client.post(
        "/v1/arenas",
        json=arena_to_dict(square()),
        headers=headers,
    )
    assert created.status_code == 200
    arena_id = UUID(created.json()["id"])
    user_id = UUID(user["user"]["id"])
    deleted = client.delete("/v1/me", headers=headers)
    assert deleted.status_code == 200

    async def check_db() -> None:
        async with client.app.state.session_factory() as session:
            assert await session.get(User, user_id) is None
            assert await session.get(ArenaRow, arena_id) is None
            rows = (
                await session.execute(select(ArenaRow).where(ArenaRow.owner_id == user_id))
            ).scalars().all()
            assert rows == []

    asyncio.run(check_db())