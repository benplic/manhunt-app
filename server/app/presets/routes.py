from fastapi import APIRouter

from app.presets.classic import CLASSIC_ID, CLASSIC_MODULES

router = APIRouter(prefix="/v1/presets", tags=["presets"])


@router.get("")
async def list_presets() -> list[dict]:
    return [
        {
            "id": CLASSIC_ID,
            "name": "Classic Manhunt",
            "modules": CLASSIC_MODULES,
        }
    ]
