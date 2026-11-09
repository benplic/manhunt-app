from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import ArenaRow
from app.engine.arena import arena_from_dict, validate_arena
from app.errors import ApiError, ErrorCode


class ArenaIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    boundary: list[dict[str, float]]
    zones: list[dict[str, Any]] = []


def bind_arena_routes(get_session, current_user):
    router = APIRouter(prefix="/v1/arenas", tags=["arenas"])

    @router.get("")
    async def list_arenas(
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> list[dict]:
        rows = (
            (await session.execute(select(ArenaRow).where(ArenaRow.owner_id == user.id)))
            .scalars()
            .all()
        )
        return [_out(row) for row in rows]

    @router.post("")
    async def create_arena(
        body: ArenaIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        data = {"name": body.name, "boundary": body.boundary, "zones": body.zones}
        _validate(data)
        row = ArenaRow(owner_id=user.id, name=body.name, data=data)
        session.add(row)
        await session.commit()
        await session.refresh(row)
        return _out(row)

    @router.get("/{arena_id}")
    async def get_arena(
        arena_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await _owned(session, user.id, arena_id)
        return _out(row)

    @router.put("/{arena_id}")
    async def update_arena(
        arena_id: UUID,
        body: ArenaIn,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await _owned(session, user.id, arena_id)
        data = {"name": body.name, "boundary": body.boundary, "zones": body.zones}
        _validate(data)
        row.name = body.name
        row.data = data
        row.version += 1
        await session.commit()
        return _out(row)

    @router.delete("/{arena_id}")
    async def delete_arena(
        arena_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await _owned(session, user.id, arena_id)
        await session.delete(row)
        await session.commit()
        return {"ok": True}

    return router


def _validate(data: dict) -> None:
    arena = arena_from_dict(data)
    issues = validate_arena(arena)
    if issues:
        raise ApiError(
            ErrorCode.ARENA_INVALID,
            "Arena failed validation.",
            status_code=422,
            details={"issues": [{"code": i.code, "name": i.name} for i in issues]},
        )


async def _owned(session: AsyncSession, user_id: UUID, arena_id: UUID) -> ArenaRow:
    row = await session.get(ArenaRow, arena_id)
    if row is None:
        raise ApiError(ErrorCode.ARENA_NOT_FOUND, "Arena not found.", status_code=404)
    if row.owner_id != user_id:
        raise ApiError(ErrorCode.FORBIDDEN, "Not your arena.", status_code=403)
    return row


def _out(row: ArenaRow) -> dict:
    payload = dict(row.data)
    payload["id"] = str(row.id)
    payload["name"] = row.name
    payload["version"] = row.version
    return payload
