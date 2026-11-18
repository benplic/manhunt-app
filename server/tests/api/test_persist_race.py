"""Concurrent event persist must not UniqueViolation; end is idempotent under race."""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.db.models import GameEventRow
from app.games.service import GameService
from tests.conftest import make_test_app
from tests.engine.helpers import make_session
from tests.sim.test_full_games import _hdr, _open_game


def test_end_is_idempotent_when_already_ended() -> None:
    session, _clock = make_session()
    hider = session.add_player(uuid4(), "Host", is_host=True)
    seeker = session.add_player(uuid4(), "Guest", is_host=False)
    session.set_role(hider.player_id, "hider")
    session.set_role(seeker.player_id, "seeker")
    session.start()
    session.end("first", winner="none")
    before = [e for e in session.state.event_log if e.type == "ended"]
    assert len(before) == 1
    session.end("second", winner="hiders")
    after = [e for e in session.state.event_log if e.type == "ended"]
    assert len(after) == 1
    assert after[0].payload["text"] == "first"
    assert session.state.phase == "ended"
    assert session.state.result is not None
    assert session.state.result.reason == "first"


def test_concurrent_persist_does_not_unique_violation(tmp_path) -> None:
    app = make_test_app(tmp_path)
    service = GameService(app.state.manager)

    with TestClient(app) as client:
        gid, _host, _hider, _seeker, _hid, _seek = _open_game(client)
        game = app.state.manager.sessions[UUID(gid)]
        assert game.state.event_log
        # Fresh event that is not yet in game_events — both flushers will see it.
        game.emit("note", {"text": "race"})

        async def flush_once() -> None:
            async with app.state.session_factory() as db:
                try:
                    # Prefer the commit=True path once implemented (lock spans commit).
                    await service.persist_game(db, game, commit=True)
                except TypeError:
                    await service.persist_game(db, game)
                    await db.commit()

        async def race() -> None:
            results = await asyncio.gather(flush_once(), flush_once(), return_exceptions=True)
            errors = [r for r in results if isinstance(r, BaseException)]
            assert not any(isinstance(e, IntegrityError) for e in errors), errors
            for err in errors:
                raise err
            async with app.state.session_factory() as db:
                seqs = (
                    await db.scalars(
                        select(GameEventRow.seq)
                        .where(GameEventRow.game_id == game.state.game_id)
                        .order_by(GameEventRow.seq)
                    )
                ).all()
                count = await db.scalar(
                    select(func.count())
                    .select_from(GameEventRow)
                    .where(GameEventRow.game_id == game.state.game_id)
                )
            assert count == len(seqs)
            assert seqs == sorted(set(seqs))
            async with app.state.session_factory() as db2:
                note_count = await db2.scalar(
                    select(func.count())
                    .select_from(GameEventRow)
                    .where(
                        GameEventRow.game_id == game.state.game_id,
                        GameEventRow.type == "note",
                    )
                )
            assert note_count == 1

        asyncio.run(race())


def test_end_under_racing_tick_persist_returns_200(tmp_path) -> None:
    app = make_test_app(tmp_path)
    service = GameService(app.state.manager)

    with TestClient(app) as client:
        gid, host, _hider, _seeker, _hid, _seek = _open_game(client)
        game = app.state.manager.sessions[UUID(gid)]
        if hasattr(game, "last_persisted_seq"):
            game.last_persisted_seq = 0

        async def tick_persist_loop(stop: asyncio.Event) -> None:
            while not stop.is_set():
                async with app.state.session_factory() as db:
                    try:
                        try:
                            await service.persist_game(db, game, commit=True)
                        except TypeError:
                            await service.persist_game(db, game)
                            await db.commit()
                    except IntegrityError as exc:
                        raise AssertionError("persist raced into UniqueViolation") from exc
                await asyncio.sleep(0)

        async def run() -> None:
            stop = asyncio.Event()
            task = asyncio.create_task(tick_persist_loop(stop))
            await asyncio.sleep(0)
            ended = await asyncio.to_thread(
                client.post,
                f"/v1/games/{gid}/end",
                headers=_hdr(host["access_token"]),
            )
            stop.set()
            await task
            assert ended.status_code == 200, ended.text
            assert ended.json()["phase"] == "ended"
            ended_again = await asyncio.to_thread(
                client.post,
                f"/v1/games/{gid}/end",
                headers=_hdr(host["access_token"]),
            )
            assert ended_again.status_code == 200, ended_again.text
            async with app.state.session_factory() as db:
                ended_rows = (
                    await db.scalars(
                        select(GameEventRow)
                        .where(
                            GameEventRow.game_id == game.state.game_id,
                            GameEventRow.type == "ended",
                        )
                        .order_by(GameEventRow.seq)
                    )
                ).all()
            assert len(ended_rows) == 1

        asyncio.run(run())
