"""Hard-delete a user account and owned personal data."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import (
    ArenaRow,
    DeviceToken,
    GameEventRow,
    GamePlayerRow,
    GameRow,
    RefreshToken,
    RulePreset,
    User,
)
from app.realtime.manager import SessionManager

_DELETED_DISPLAY = "Deleted player"


def _anonymize_live_player(manager: SessionManager, game_id: UUID, user_id: UUID) -> None:
    live = manager.get(game_id)
    if live is None:
        return
    player = live.state.players.get(user_id)
    if player is None:
        return
    player.display_name = _DELETED_DISPLAY
    live.state.players.pop(user_id, None)


async def delete_account(
    session: AsyncSession,
    user: User,
    *,
    manager: SessionManager | None = None,
) -> None:
    user_id = user.id

    hosted_game_ids = (
        await session.execute(select(GameRow.id).where(GameRow.host_id == user_id))
    ).scalars().all()
    for game_id in hosted_game_ids:
        if manager is not None:
            manager.sessions.pop(game_id, None)
            manager.sockets.pop(game_id, None)
        await session.execute(delete(GameEventRow).where(GameEventRow.game_id == game_id))
        await session.execute(delete(GamePlayerRow).where(GamePlayerRow.game_id == game_id))
    if hosted_game_ids:
        await session.execute(delete(GameRow).where(GameRow.host_id == user_id))

    memberships = (
        await session.execute(select(GamePlayerRow).where(GamePlayerRow.user_id == user_id))
    ).scalars().all()
    for member in memberships:
        if manager is not None:
            _anonymize_live_player(manager, member.game_id, user_id)
            manager.detach(member.game_id, user_id)
        await session.delete(member)

    await session.execute(delete(RefreshToken).where(RefreshToken.user_id == user_id))
    device = await session.get(DeviceToken, user_id)
    if device is not None:
        await session.delete(device)
    await session.execute(delete(ArenaRow).where(ArenaRow.owner_id == user_id))
    await session.execute(delete(RulePreset).where(RulePreset.owner_id == user_id))
    await session.delete(user)