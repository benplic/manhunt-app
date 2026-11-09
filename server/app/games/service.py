from __future__ import annotations

import random
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import ArenaRow, GameEventRow, GamePlayerRow, GameRow, User
from app.engine.arena import arena_from_dict, arena_to_dict, validate_arena
from app.engine.modules.base import TagClaim
from app.engine.qr import parse_qr_token
from app.engine.session import GameSession
from app.engine.views import build_view
from app.errors import ApiError, ErrorCode, GameRuleError
from app.games.join_code import generate, is_valid, normalize
from app.presets.classic import CLASSIC_ID, classic_preset
from app.realtime.manager import SessionManager


def _http_for_rule(exc: GameRuleError) -> ApiError:
    status = 409
    if exc.code in {ErrorCode.UNAUTHORIZED, ErrorCode.TOKEN_INVALID, ErrorCode.TOKEN_EXPIRED}:
        status = 401
    return ApiError(exc.code, exc.message, status_code=status)


class GameService:
    def __init__(self, manager: SessionManager) -> None:
        self.manager = manager

    async def create(
        self,
        session: AsyncSession,
        host: User,
        arena_id: UUID,
        preset_id: str,
        overrides: dict[str, dict[str, Any]] | None,
    ) -> GameRow:
        arena_row = await session.get(ArenaRow, arena_id)
        if arena_row is None:
            raise ApiError(ErrorCode.ARENA_NOT_FOUND, "Arena not found.", status_code=404)
        if preset_id != CLASSIC_ID:
            raise ApiError(ErrorCode.PRESET_NOT_FOUND, "Unknown preset.", status_code=404)
        preset = classic_preset(overrides, validate=True)
        arena = arena_from_dict(arena_row.data)
        issues = validate_arena(arena)
        if issues:
            raise ApiError(
                ErrorCode.ARENA_INVALID,
                "Arena is not playable.",
                status_code=422,
                details={"issues": [i.code for i in issues]},
            )
        join_code = await self._unique_code(session)
        seed = random.SystemRandom().randint(1, 2**31 - 1)
        row = GameRow(
            id=uuid4(),
            join_code=join_code,
            host_id=host.id,
            status="lobby",
            arena_snapshot=arena_to_dict(arena),
            preset_snapshot=preset,
            seed=seed,
            inputs=[],
        )
        session.add(row)
        session.add(GamePlayerRow(game_id=row.id, user_id=host.id, role="unassigned"))
        await session.commit()
        game = self.manager.register(
            row.id, row.arena_snapshot, row.preset_snapshot, seed, join_code
        )
        game.add_player(host.id, host.display_name, is_host=True)
        return row

    async def join(self, session: AsyncSession, user: User, code: str) -> GameRow:
        if not is_valid(code):
            raise ApiError(ErrorCode.INVALID_JOIN_CODE, "Codes are 6 characters.", status_code=422)
        row = await session.scalar(
            select(GameRow).where(
                GameRow.join_code == normalize(code),
                GameRow.status.notin_(["ended", "abandoned"]),
            )
        )
        if row is None:
            raise ApiError(ErrorCode.GAME_NOT_FOUND, "No game is using that code.", status_code=404)
        existing = await session.get(GamePlayerRow, (row.id, user.id))
        if existing is None:
            from sqlalchemy import func

            count = await session.scalar(
                select(func.count())
                .select_from(GamePlayerRow)
                .where(GamePlayerRow.game_id == row.id)
            )
            if (count or 0) >= 20:
                raise ApiError(ErrorCode.GAME_FULL, "This lobby is full.", status_code=409)
            session.add(GamePlayerRow(game_id=row.id, user_id=user.id))
            await session.commit()
            game = self._live(row)
            game.add_player(user.id, user.display_name, is_host=False)
        return row

    def _live(self, row: GameRow) -> GameSession:
        game = self.manager.get(row.id)
        if game is None:
            game = self.manager.register(
                row.id, row.arena_snapshot, row.preset_snapshot, row.seed, row.join_code
            )
        return game

    async def require_member(
        self, session: AsyncSession, game_id: UUID, user: User
    ) -> tuple[GameRow, GamePlayerRow]:
        row = await session.get(GameRow, game_id)
        if row is None:
            raise ApiError(ErrorCode.GAME_NOT_FOUND, "Game not found.", status_code=404)
        member = await session.get(GamePlayerRow, (game_id, user.id))
        if member is None:
            raise ApiError(ErrorCode.NOT_A_MEMBER, "You are not in this game.", status_code=403)
        return row, member

    async def require_host(self, session: AsyncSession, game_id: UUID, user: User) -> GameRow:
        row, _ = await self.require_member(session, game_id, user)
        if row.host_id != user.id:
            raise ApiError(ErrorCode.NOT_HOST, "Only the host can do that.", status_code=403)
        return row

    async def set_roles(
        self,
        session: AsyncSession,
        user: User,
        game_id: UUID,
        body: dict[str, Any],
    ) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        mode = body.get("mode")
        if mode == "random":
            game.assign_roles_random(int(body.get("hider_count", 1)))
        elif mode == "manual":
            for player_id, role in (body.get("assignments") or {}).items():
                game.set_role(UUID(str(player_id)), str(role))
        else:
            raise ApiError(
                ErrorCode.VALIDATION_FAILED, "mode must be random or manual.", status_code=422
            )
        for player in game.state.players.values():
            member = await session.get(GamePlayerRow, (game_id, player.player_id))
            if member:
                member.role = player.role
        await session.commit()
        return game

    async def start(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        try:
            game.start()
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        row.status = game.state.phase
        row.started_at = datetime.now(UTC)
        await session.commit()
        return game

    async def pause(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        try:
            game.pause()
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        row.status = game.state.phase
        await session.commit()
        return game

    async def resume(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        try:
            game.resume()
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        row.status = game.state.phase
        await session.commit()
        return game

    async def end(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        game.end("The host ended the hunt.", winner="none")
        row.status = "ended"
        row.ended_at = datetime.now(UTC)
        await self.persist_inputs(session, game)
        await session.commit()
        return game

    async def remove_player(
        self, session: AsyncSession, user: User, game_id: UUID, player_id: UUID
    ) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        try:
            game.remove_player(player_id)
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        member = await session.get(GamePlayerRow, (game_id, player_id))
        if member:
            await session.delete(member)
        await self.persist_inputs(session, game)
        await session.commit()
        return game

    async def undo_tag(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        try:
            game.undo_tag()
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        await self.persist_inputs(session, game)
        await session.commit()
        return game

    async def purchase(
        self, session: AsyncSession, user: User, game_id: UUID, power_id: str, extra: dict
    ) -> GameSession:
        row, _ = await self.require_member(session, game_id, user)
        game = self._live(row)
        try:
            game.purchase(user.id, power_id, **extra)
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        await self.persist_inputs(session, game)
        await session.commit()
        return game

    async def taunt(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row, _ = await self.require_member(session, game_id, user)
        game = self._live(row)
        try:
            game.taunt(user.id)
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        await self.persist_inputs(session, game)
        await session.commit()
        return game

    async def ack_safety(self, session: AsyncSession, user: User, game_id: UUID) -> GameSession:
        row = await self.require_host(session, game_id, user)
        game = self._live(row)
        try:
            game.ack_safety(user.id)
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        await session.commit()
        return game

    async def qr_tag(self, session: AsyncSession, user: User, game_id: UUID, token: str) -> None:
        row, _ = await self.require_member(session, game_id, user)
        game = self._live(row)
        try:
            hider_id = parse_qr_token(
                token, game_id=game.state.game_id, key=game.qr_signing_key, now=game.clock.now()
            )
            game.claim_tag(TagClaim(user.id, hider_id, qr_token=token))
        except GameRuleError as exc:
            raise _http_for_rule(exc) from exc
        await self._persist_events(session, game)
        row.status = game.state.phase
        await session.commit()

    async def persist_inputs(self, session: AsyncSession, game: GameSession) -> None:
        row = await session.get(GameRow, game.state.game_id)
        if row is not None:
            row.inputs = list(game.state.inputs)
            row.status = game.state.phase
            if game.state.result:
                row.result = {
                    "winner": game.state.result.winner,
                    "reason": game.state.result.reason,
                }

    async def _persist_events(self, session: AsyncSession, game: GameSession) -> None:
        from app.config import get_settings
        from app.crypto import encrypt_payload, load_trail_key

        settings = get_settings()
        try:
            key = load_trail_key(settings.manhunt_trail_key)
        except Exception:
            key = None
        for event in game.drain_events():
            payload: dict = {"text": event.text, "tone": event.tone}
            if event.sensitive:
                if key is None:
                    continue
                payload = encrypt_payload(key, event.payload, settings.manhunt_trail_key_id)
            session.add(
                GameEventRow(
                    game_id=game.state.game_id,
                    seq=event.seq,
                    type=event.type,
                    payload=payload,
                    sensitive=event.sensitive,
                )
            )
        await self.persist_inputs(session, game)

    async def view(self, session: AsyncSession, user: User, game_id: UUID) -> dict:
        row, _ = await self.require_member(session, game_id, user)
        game = self._live(row)
        # Rebuild players if the process just started.
        if not game.state.players:
            members = (
                await session.execute(select(GamePlayerRow).where(GamePlayerRow.game_id == game_id))
            ).scalars()
            for member in members:
                person = await session.get(User, member.user_id)
                if person:
                    player = game.add_player(
                        person.id, person.display_name, person.id == row.host_id
                    )
                    player.role = member.role
                    player.status = member.status
        return build_view(game, user.id)

    async def _unique_code(self, session: AsyncSession) -> str:
        for _ in range(20):
            code = generate()
            taken = await session.scalar(
                select(GameRow.id).where(
                    GameRow.join_code == code,
                    GameRow.status.notin_(["ended", "abandoned"]),
                )
            )
            if taken is None:
                return code
        raise ApiError(ErrorCode.INTERNAL, "Could not allocate a join code.", status_code=500)
