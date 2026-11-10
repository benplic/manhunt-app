"""Classic Manhunt module defaults. Formal JSON Schema arrives in Phase 5."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from app.errors import ApiError, ErrorCode

CLASSIC_ID = "classic"

CLASSIC_MODULES: dict[str, dict[str, Any]] = {
    "roles": {"mode": "random", "hider_count": 2},
    "head_start": {"enabled": True, "duration": 60, "seeker_lock": "locked_map"},
    "reveal_fuzzy": {"enabled": True, "interval": 60, "display": 10, "fuzz": 30},
    "tag_policy": {
        "method": "qr",
        "radius_m": 2,
        "result": "eliminate",
        "pairing_m": 30,
    },
    "zone_policy": {
        "margin_m": 5,
        "oob_countdown": 15,
        "hider_oob_penalty": "auto_tag",
        "seeker_oob_penalty": "forced_reveal",
        "safe_visit": 60,
        "safe_cooldown": 60,
    },
    "signal_loss": {"silence": 45, "penalty_after": 180, "penalty": "none"},
    "win": {"condition": "either", "time_limit": 30},
    "hot_cold": {"enabled": True, "interval": 5},
    "points": {
        "survival_s": 300,
        "survival_points": 10,
        "close_m": 15,
        "escape_m": 30,
        "close_hold_s": 5,
        "close_call_points": 20,
        "others_tagged_points": 15,
        "taunt_s": 8,
    },
    "power_ups": {"enabled": True},
    "effects": {},
}

RANGES: dict[tuple[str, str], tuple[float, float]] = {
    ("roles", "hider_count"): (1, 20),
    ("head_start", "duration"): (15, 600),
    ("reveal_fuzzy", "interval"): (20, 600),
    ("reveal_fuzzy", "display"): (5, 60),
    ("reveal_fuzzy", "fuzz"): (0, 100),
    ("tag_policy", "radius_m"): (1, 5),
    ("tag_policy", "pairing_m"): (5, 80),
    ("zone_policy", "margin_m"): (0, 30),
    ("zone_policy", "oob_countdown"): (5, 120),
    ("zone_policy", "safe_visit"): (5, 300),
    ("zone_policy", "safe_cooldown"): (0, 300),
    ("signal_loss", "silence"): (15, 300),
    ("signal_loss", "penalty_after"): (30, 900),
    ("win", "time_limit"): (5, 180),
    ("hot_cold", "interval"): (2, 30),
}


def classic_preset(
    overrides: dict[str, dict[str, Any]] | None = None,
    *,
    validate: bool = False,
) -> dict[str, Any]:
    modules = deepcopy(CLASSIC_MODULES)
    if overrides:
        if validate:
            validate_overrides(overrides)
        for module_id, fields in overrides.items():
            if module_id not in modules:
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"Unknown module {module_id}.",
                    status_code=422,
                )
            modules[module_id].update(fields)
    return {"id": CLASSIC_ID, "name": "Classic Manhunt", "modules": modules}


def validate_overrides(overrides: dict[str, dict[str, Any]]) -> None:
    for module_id, fields in overrides.items():
        for key, value in fields.items():
            bounds = RANGES.get((module_id, key))
            if bounds is None:
                continue
            try:
                number = float(value)
            except (TypeError, ValueError) as exc:
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"{module_id}.{key} must be a number.",
                    status_code=422,
                ) from exc
            lo, hi = bounds
            if number < lo or number > hi:
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"{module_id}.{key} must be between {lo} and {hi}.",
                    status_code=422,
                    details={"field": f"{module_id}.{key}"},
                )
