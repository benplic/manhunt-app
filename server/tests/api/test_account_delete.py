"""DELETE /v1/me removes personal data and invalidates refresh tokens."""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.db.models import ArenaRow, User
from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


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