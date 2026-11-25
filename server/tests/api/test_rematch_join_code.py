"""Rematch keeps the ended game's join code, and handles the edges around that."""

from __future__ import annotations

import asyncio
from uuid import UUID

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.db.models import GameRow, User
from tests.api.test_rematch import _auth, _ended_game, _headers


def _rows_with_code(client: TestClient, code: str) -> list[tuple[str, str]]:
    async def read() -> list[tuple[str, str]]:
        async with client.app.state.session_factory() as db:
            rows = (
                await db.scalars(select(GameRow).where(GameRow.join_code == code))
            ).all()
            return [(str(row.id), row.status) for row in rows]

    return client.portal.call(read)


def _set_code(client: TestClient, game_id: str, code: str) -> None:
    async def write() -> None:
        async with client.app.state.session_factory() as db:
            row = await db.get(GameRow, UUID(game_id))
            assert row is not None
            row.join_code = code
            await db.commit()

    client.portal.call(write)


def _make_live_game(client: TestClient, host_token: str) -> dict:
    from app.engine.arena import arena_to_dict
    from tests.engine.helpers import square

    headers = _headers(host_token)
    arena = client.post("/v1/arenas", json=arena_to_dict(square()), headers=headers)
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic"},
        headers=headers,
    )
    assert game.status_code == 200, game.text
    return game.json()


def test_rematch_reuses_the_join_code_and_guest_old_code_lands_in_new_lobby(
    client: TestClient,
) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)

    rematch = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])
    assert rematch.status_code == 200, rematch.text
    new_id = rematch.json()["game_id"]
    assert rematch.json()["join_code"] == ended["join_code"]

    # Only the new lobby is live under that code. The ended row keeps it as history.
    statuses = dict(_rows_with_code(client, ended["join_code"]))
    assert statuses[ended["id"]] == "ended"
    assert statuses[new_id] == "lobby"

    guest_join = client.post(
        "/v1/games/join",
        json={"join_code": ended["join_code"]},
        headers=_headers(ended["guest"]["access_token"]),
    )
    assert guest_join.status_code == 200, guest_join.text
    assert guest_join.json()["id"] == new_id


def test_tick_persist_of_the_ended_game_does_not_forget_the_rematch(
    client: TestClient,
) -> None:
    """The 1 Hz persist rewrites games.result for ended games. It must keep the link."""
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    first = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])
    assert first.status_code == 200, first.text

    old_game = client.app.state.manager.sessions[UUID(ended["id"])]

    async def persist_old() -> None:
        async with client.app.state.session_factory() as db:
            await client.app.state.game_service.persist_game(db, old_game, commit=True)

    client.portal.call(persist_old)

    again = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])
    assert again.status_code == 200, again.text
    assert again.json()["game_id"] == first.json()["game_id"]
    assert len(_rows_with_code(client, ended["join_code"])) == 2

    guest = client.post(
        f"/v1/games/{ended['id']}/rematch",
        headers=_headers(ended["guest"]["access_token"]),
    )
    assert guest.status_code == 200, guest.text
    assert guest.json()["game_id"] == first.json()["game_id"]


def test_host_tapping_rematch_twice_returns_the_same_lobby(client: TestClient) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)

    first = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])
    second = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])

    assert first.json()["game_id"] == second.json()["game_id"]
    assert first.json()["join_code"] == second.json()["join_code"] == ended["join_code"]


def test_simultaneous_host_rematch_requests_create_one_lobby(client: TestClient) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    service = client.app.state.game_service
    host_id = UUID(host["user"]["id"])

    async def one_request() -> str:
        async with client.app.state.session_factory() as db:
            user = await db.get(User, host_id)
            assert user is not None
            game = await service.rematch(db, user, UUID(ended["id"]))
            return str(game.state.game_id)

    async def race() -> list[str]:
        return list(await asyncio.gather(*(one_request() for _ in range(5))))

    ids = client.portal.call(race)

    assert len(set(ids)) == 1
    live = [row for row in _rows_with_code(client, ended["join_code"]) if row[1] == "lobby"]
    assert len(live) == 1


def test_rematch_falls_back_to_a_new_code_when_another_live_game_took_it(
    client: TestClient,
) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    other_host = _auth(client, "Morgan")
    other = _make_live_game(client, other_host["access_token"])
    # The old code was released when the hunt ended, so a new game may hold it.
    _set_code(client, other["id"], ended["join_code"])

    rematch = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])

    assert rematch.status_code == 200, rematch.text
    assert rematch.json()["join_code"] != ended["join_code"]
    live = [row for row in _rows_with_code(client, ended["join_code"]) if row[1] != "ended"]
    assert [row[0] for row in live] == [other["id"]]


def test_rematch_of_the_sample_game_does_not_reuse_park42(client: TestClient) -> None:
    """PARK42 is a reserved demo code. A normal lobby must never sit on it."""
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    _set_code(client, ended["id"], "PARK42")
    client.app.state.manager.sessions[UUID(ended["id"])].state.join_code = "PARK42"

    rematch = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])

    assert rematch.status_code == 200, rematch.text
    assert rematch.json()["join_code"] != "PARK42"


def test_guest_joining_with_old_code_before_host_rematches_is_not_found(
    client: TestClient,
) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)

    joined = client.post(
        "/v1/games/join",
        json={"join_code": ended["join_code"]},
        headers=_headers(ended["guest"]["access_token"]),
    )

    assert joined.status_code == 404
    assert joined.json()["error"]["code"] == "GAME_NOT_FOUND"


def test_rematch_lobby_keeps_players_who_were_already_carried_over(
    client: TestClient,
) -> None:
    host = _auth(client, "Casey")
    ended = _ended_game(client, host)
    host_rematch = client.post(f"/v1/games/{ended['id']}/rematch", headers=ended["headers"])
    guest_rematch = client.post(
        f"/v1/games/{ended['id']}/rematch",
        headers=_headers(ended["guest"]["access_token"]),
    )
    assert guest_rematch.status_code == 200, guest_rematch.text

    # The guest already has a seat. Joining by the shared code again is idempotent.
    rejoin = client.post(
        "/v1/games/join",
        json={"join_code": ended["join_code"]},
        headers=_headers(ended["guest"]["access_token"]),
    )

    assert rejoin.status_code == 200
    assert rejoin.json()["id"] == host_rematch.json()["game_id"]
    view = client.get(
        f"/v1/games/{host_rematch.json()['game_id']}", headers=ended["headers"]
    ).json()
    assert len(view["players"]) == 2
