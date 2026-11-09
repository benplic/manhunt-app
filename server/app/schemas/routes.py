from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import RulePreset
from app.schemas.modules import SCHEMAS

router = APIRouter(prefix="/v1", tags=["schemas"])


@router.get("/modules")
async def list_modules() -> dict:
    return {"modules": SCHEMAS}


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

    return extra
