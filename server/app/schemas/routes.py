from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import RulePreset
from app.errors import ApiError, ErrorCode
from app.schemas.modules import SCHEMAS

router = APIRouter(prefix="/v1", tags=["schemas"])


@router.get("/modules")
async def list_modules() -> dict:
    # `order` is the form order. Dict key order is not part of the contract.
    return {"modules": SCHEMAS, "order": list(SCHEMAS)}


def bind_preset_save(get_session, current_user):
    extra = APIRouter(prefix="/v1/presets", tags=["presets"])

    @extra.post("/saved")
    async def save_preset(
        body: dict,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = RulePreset(
            owner_id=user.id,
            name=str(body.get("name", "Custom")),
            modules=body.get("modules") or {},
        )
        session.add(row)
        await session.commit()
        await session.refresh(row)
        return {"id": str(row.id), "name": row.name, "modules": row.modules}

    @extra.get("/saved")
    async def list_saved(
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> list[dict]:
        rows = (
            await session.execute(select(RulePreset).where(RulePreset.owner_id == user.id))
        ).scalars()
        return [{"id": str(r.id), "name": r.name, "modules": r.modules} for r in rows]

    @extra.put("/saved/{preset_id}")
    async def update_preset(
        preset_id: UUID,
        body: dict,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await _owned_preset(session, user.id, preset_id)
        row.name = str(body.get("name", "Custom"))[:80]
        row.modules = body.get("modules") or {}
        row.version += 1
        await session.commit()
        await session.refresh(row)
        return {"id": str(row.id), "name": row.name, "modules": row.modules}

    @extra.delete("/saved/{preset_id}")
    async def delete_preset(
        preset_id: UUID,
        session: AsyncSession = Depends(get_session),
        user=Depends(current_user),
    ) -> dict:
        row = await _owned_preset(session, user.id, preset_id)
        await session.delete(row)
        await session.commit()
        return {"ok": True}

    return extra


async def _owned_preset(session: AsyncSession, user_id: UUID, preset_id: UUID) -> RulePreset:
    row = await session.get(RulePreset, preset_id)
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Preset not found.", status_code=404)
    if row.owner_id != user_id:
        raise ApiError(ErrorCode.FORBIDDEN, "Not your preset.", status_code=403)
    return row
