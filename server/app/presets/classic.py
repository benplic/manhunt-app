"""Classic Manhunt module defaults. Formal JSON Schema arrives in Phase 5."""

from __future__ import annotations

import math
from copy import deepcopy
from typing import Any

from app.errors import ApiError, ErrorCode
from app.limits import MAX_GAME_PLAYERS

CLASSIC_ID = "classic"

CLASSIC_MODULES: dict[str, dict[str, Any]] = {
    "roles": {"mode": "random", "seeker_count": 1},
    "head_start": {"enabled": True, "duration": 60, "seeker_lock": "locked_map"},
    "reveal_fuzzy": {
        "location_mode": "fuzzy",
        "persistence": "timed",
        "interval": 60,
        "display": 10,
        "fuzz": 30,
        "hints_enabled": True,
        "hints_persistence": "persistent",
        "hints_interval": 5,
    },
    "reveal_seekers": {
        "location_mode": "off",
        "persistence": "timed",
        "interval": 60,
        "display": 10,
        "fuzz": 30,
        "hints_enabled": True,
        "hints_persistence": "persistent",
        "hints_interval": 5,
    },
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
        "safe_remove_after": 0,
    },
    "zone_shrink": {
        "enabled": False,
        "every": 5,
        "shrink_to": 75,
        "min_radius_m": 50,
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
        "taunt_enabled": True,
        "taunt_s": 8,
        "taunt_cooldown": 45,
    },
    "power_ups": {
        "enabled": True,
        "ghost_enabled": True,
        "ghost_cost": 20,
        "decoy_enabled": True,
        "decoy_cost": 40,
        "radar_enabled": True,
        "radar_cost": 40,
        "jammer_enabled": True,
        "jammer_cost": 55,
        "shield_enabled": True,
        "shield_cost": 70,
        "rescue_enabled": True,
        "rescue_cost": 120,
        "rescue_duration": 60,
        "create_safe_enabled": True,
        "create_safe_cost": 110,
        "create_safe_radius_m": 30,
        "scan_enabled": True,
        "scan_cost": 25,
        "scan_radius_m": 30,
        "scan_count": 1,
        "tracker_enabled": True,
        "tracker_cost": 50,
        "lockdown_enabled": True,
        "lockdown_cost": 75,
        "move_safe_enabled": True,
        "move_safe_cost": 110,
        "shrink_now_enabled": True,
        "shrink_now_cost": 100,
    },
    "effects": {},
}

RANGES: dict[tuple[str, str], tuple[float, float]] = {
    ("roles", "seeker_count"): (1, MAX_GAME_PLAYERS),
    ("head_start", "duration"): (15, 600),
    ("reveal_fuzzy", "interval"): (20, 600),
    ("reveal_fuzzy", "display"): (5, 60),
    ("reveal_fuzzy", "fuzz"): (0, 100),
    ("tag_policy", "radius_m"): (1, 5),
    ("tag_policy", "pairing_m"): (30, 30),
    ("zone_policy", "margin_m"): (0, 30),
    ("zone_policy", "oob_countdown"): (5, 120),
    ("zone_policy", "safe_visit"): (5, 300),
    ("zone_policy", "safe_cooldown"): (0, 300),
    ("zone_policy", "safe_remove_after"): (0, 180),
    ("power_ups", "scan_radius_m"): (10, 150),
    ("power_ups", "scan_count"): (1, 5),
    ("power_ups", "rescue_duration"): (15, 180),
    ("power_ups", "create_safe_radius_m"): (10, 80),
    ("zone_shrink", "every"): (1, 30),
    ("zone_shrink", "shrink_to"): (50, 95),
    ("zone_shrink", "min_radius_m"): (30, 500),
    ("signal_loss", "silence"): (15, 300),
    ("signal_loss", "penalty_after"): (30, 900),
    ("win", "time_limit"): (5, 180),
    ("hot_cold", "interval"): (2, 30),
    ("reveal_fuzzy", "hints_interval"): (2, 30),
    ("reveal_seekers", "interval"): (20, 600),
    ("reveal_seekers", "display"): (5, 60),
    ("reveal_seekers", "fuzz"): (0, 100),
    ("reveal_seekers", "hints_interval"): (2, 30),
    ("points", "taunt_cooldown"): (10, 180),
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


def validate_rule_edits(overrides: dict[str, dict[str, Any]]) -> None:
    """Stricter than `validate_overrides`, for edits to a game that already exists.

    Creation tolerates unknown keys; a lobby edit does not, so a typo cannot silently
    persist into the replay snapshot. Every key must exist in the Classic defaults. Values
    are then checked against the module schema (type, range, enum values) that the preset
    editor renders from, and finally against the numeric RANGES the engine relies on.
    """
    from app.schemas.modules import SCHEMAS

    if not overrides:
        raise ApiError(ErrorCode.VALIDATION_FAILED, "No rule changes given.", status_code=422)
    for module_id, fields in overrides.items():
        defaults = CLASSIC_MODULES.get(module_id)
        if defaults is None or not isinstance(fields, dict):
            raise ApiError(
                ErrorCode.VALIDATION_FAILED,
                f"Unknown module {module_id}.",
                status_code=422,
            )
        schema_fields = SCHEMAS.get(module_id, {}).get("fields", {})
        for key, value in fields.items():
            if key not in defaults:
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"Unknown rule {module_id}.{key}.",
                    status_code=422,
                    details={"field": f"{module_id}.{key}"},
                )
            if not _value_allowed(defaults[key], schema_fields.get(key), value):
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"{module_id}.{key} has an invalid value.",
                    status_code=422,
                    details={"field": f"{module_id}.{key}"},
                )
    validate_overrides(overrides)


def _is_number(value: Any) -> bool:
    # bool is an int subclass in Python, so it must never pass as a number. NaN and
    # Infinity parse from JSON and slip past every range comparison, so reject them here.
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        # An int too large for a float.
        return False


def _value_allowed(default: Any, field: dict[str, Any] | None, value: Any) -> bool:
    """True when `value` fits the schema field, or the default's JSON type when no schema."""
    kind = field.get("type") if field else None
    if kind == "enum":
        return isinstance(value, str) and value in field["values"]
    if kind == "bool" or (kind is None and isinstance(default, bool)):
        return isinstance(value, bool)
    if kind in {"int", "number"} or (
        kind is None and isinstance(default, (int, float)) and not isinstance(default, bool)
    ):
        if not _is_number(value):
            return False
        if (kind == "int" or isinstance(default, int)) and float(value) != int(value):
            return False
        if field and "min" in field and "max" in field:
            return field["min"] <= float(value) <= field["max"]
        # No schema range: numbers are still bounded so a cost or duration cannot go negative
        # or absurdly large.
        return 0 <= float(value) <= 100_000
    if isinstance(default, str):
        return isinstance(value, str)
    return True

def validate_overrides(overrides: dict[str, dict[str, Any]]) -> None:
    for module_id, fields in overrides.items():
        for key, value in fields.items():
            bounds = RANGES.get((module_id, key))
            if bounds is None:
                continue
            try:
                number = float(value)
            except (TypeError, ValueError, OverflowError) as exc:
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"{module_id}.{key} must be a number.",
                    status_code=422,
                ) from exc
            lo, hi = bounds
            if not math.isfinite(number) or number < lo or number > hi:
                raise ApiError(
                    ErrorCode.VALIDATION_FAILED,
                    f"{module_id}.{key} must be between {lo} and {hi}.",
                    status_code=422,
                    details={"field": f"{module_id}.{key}"},
                )
