"""Versioned module settings schemas. Older versions migrate forward on load."""

from __future__ import annotations

from typing import Any

SCHEMAS: dict[str, dict[str, Any]] = {
    "roles": {
        "version": 1,
        "fields": {
            "mode": {"type": "enum", "values": ["random", "manual"], "default": "random"},
            "hider_count": {"type": "int", "min": 1, "max": 20, "default": 2},
        },
    },
    "head_start": {
        "version": 1,
        "fields": {
            "enabled": {"type": "bool", "default": True},
            "duration": {"type": "int", "min": 15, "max": 600, "default": 60},
            "seeker_lock": {
                "type": "enum",
                "values": ["locked_map", "spawn_zone"],
                "default": "locked_map",
            },
        },
    },
    "reveal_fuzzy": {
        "version": 1,
        "fields": {
            "interval": {"type": "int", "min": 20, "max": 600, "default": 60},
            "display": {"type": "int", "min": 5, "max": 60, "default": 10},
            "fuzz": {"type": "int", "min": 0, "max": 100, "default": 30},
        },
    },
    "tag_policy": {
        "version": 1,
        "fields": {
            "method": {"type": "enum", "values": ["qr", "uwb"], "default": "qr"},
            "radius_m": {"type": "number", "min": 1, "max": 5, "default": 2},
        },
    },
    "zone_policy": {
        "version": 1,
        "fields": {"oob_countdown": {"type": "int", "min": 5, "max": 120}},
    },
    "signal_loss": {
        "version": 1,
        "fields": {"silence": {"type": "int", "min": 15, "max": 300}},
    },
    "win": {"version": 1, "fields": {"time_limit": {"type": "int", "min": 5, "max": 180}}},
    "hot_cold": {"version": 1, "fields": {"enabled": {"type": "bool", "default": True}}},
    "points": {"version": 1, "fields": {}},
    "power_ups": {"version": 1, "fields": {}},
    "effects": {"version": 1, "fields": {}},
}


def migrate_settings(module_id: str, settings: dict[str, Any], from_version: int = 1) -> dict:
    """Forward-migrate older settings. v1 is the current shape; unknown keys stay."""
    schema = SCHEMAS.get(module_id)
    if schema is None:
        return settings
    current = schema["version"]
    migrated = dict(settings)
    # TODO: add named migrations when a module ships v2.
    _ = from_version, current
    return migrated
