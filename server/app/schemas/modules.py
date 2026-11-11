"""Versioned module settings schemas. Older versions migrate forward on load.

The iOS preset editor renders from this document (`GET /v1/modules`). Field order is
explicit because JSON objects do not define an order the client can rely on.
"""

from __future__ import annotations

from typing import Any


def _int(
    title: str, lo: int, hi: int, default: int, step: int = 1, suffix: str = ""
) -> dict[str, Any]:
    return {
        "type": "int",
        "title": title,
        "min": lo,
        "max": hi,
        "step": step,
        "default": default,
        "suffix": suffix,
    }


def _number(
    title: str, lo: float, hi: float, default: float, step: float = 1, suffix: str = ""
) -> dict[str, Any]:
    return {
        "type": "number",
        "title": title,
        "min": lo,
        "max": hi,
        "step": step,
        "default": default,
        "suffix": suffix,
    }


def _bool(title: str, default: bool) -> dict[str, Any]:
    return {"type": "bool", "title": title, "default": default}


def _enum(
    title: str, values: list[str], default: str, labels: list[str] | None = None
) -> dict[str, Any]:
    field: dict[str, Any] = {"type": "enum", "title": title, "values": values, "default": default}
    if labels is not None:
        field["labels"] = labels
    return field


SCHEMAS: dict[str, dict[str, Any]] = {
    "roles": {
        "version": 1,
        "title": "Roles",
        "blurb": "How hiders and seekers are chosen in the lobby.",
        "field_order": ["mode", "hider_count"],
        "fields": {
            "mode": _enum("Assignment", ["random", "manual"], "random", ["Random", "Manual"]),
            "hider_count": _int("Hiders", 1, 20, 2),
        },
    },
    "head_start": {
        "version": 1,
        "title": "Head start",
        "blurb": "Hiders hide before seekers are released.",
        "field_order": ["enabled", "duration", "seeker_lock"],
        "fields": {
            "enabled": _bool("Enabled", True),
            "duration": _int("Duration", 15, 600, 60, step=15, suffix="s"),
            "seeker_lock": _enum(
                "Seekers wait",
                ["locked_map", "spawn_zone"],
                "locked_map",
                ["Locked map", "Spawn zone"],
            ),
        },
    },
    "reveal_fuzzy": {
        "version": 1,
        "title": "Fuzzy reveal",
        "blurb": "Seekers see approximate hider pins on a timer.",
        "field_order": ["enabled", "interval", "display", "fuzz"],
        "fields": {
            "enabled": _bool("Enabled", True),
            "interval": _int("Every", 20, 600, 60, step=10, suffix="s"),
            "display": _int("Pin stays", 5, 60, 10, step=5, suffix="s"),
            "fuzz": _int("Fuzz", 0, 100, 30, step=5, suffix="m"),
        },
    },
    "tag_policy": {
        "version": 1,
        "title": "Tag",
        "blurb": "Ultra Wideband confirms the tag. A rotating code is the fallback.",
        "field_order": ["method", "radius_m", "result", "pairing_m"],
        "fields": {
            "method": _enum("Method", ["qr", "uwb"], "qr", ["QR code", "Ultra Wideband"]),
            "radius_m": _number("Radius", 1, 5, 2, step=0.5, suffix="m"),
            "result": _enum(
                "Result",
                ["eliminate", "convert"],
                "eliminate",
                ["Eliminate", "Join seekers"],
            ),
            "pairing_m": _int("Pairing", 5, 80, 30, step=5, suffix="m"),
        },
    },
    "zone_policy": {
        "version": 1,
        "title": "Zones",
        "blurb": "Out of bounds counts down. Safe zones block tags until time runs out.",
        "field_order": [
            "oob_countdown",
            "hider_oob_penalty",
            "safe_visit",
            "safe_cooldown",
            "margin_m",
        ],
        "fields": {
            "oob_countdown": _int("Out of bounds", 5, 120, 15, step=5, suffix="s"),
            "hider_oob_penalty": _enum(
                "Hider penalty",
                ["auto_tag", "forced_reveal"],
                "auto_tag",
                ["Auto-tag", "Forced reveal"],
            ),
            "safe_visit": _int("Safe visit", 5, 300, 60, step=15, suffix="s"),
            "safe_cooldown": _int("Safe cooldown", 0, 300, 60, step=15, suffix="s"),
            "margin_m": _int("Edge margin", 0, 30, 5, suffix="m"),
        },
    },
    "signal_loss": {
        "version": 1,
        "title": "Going dark",
        "blurb": "Silence shares the last precise location. Safety overrides the game.",
        "field_order": ["silence", "penalty_after", "penalty"],
        "fields": {
            "silence": _int("Call it dark after", 15, 300, 45, step=15, suffix="s"),
            "penalty_after": _int("Penalty after", 30, 900, 180, step=30, suffix="s"),
            "penalty": _enum("Penalty", ["none", "eliminate"], "none", ["None", "Eliminate"]),
        },
    },
    "win": {
        "version": 1,
        "title": "Win",
        "blurb": "How the hunt ends.",
        "field_order": ["condition", "time_limit"],
        "fields": {
            "condition": _enum(
                "Ends when",
                ["all_caught", "time_limit", "either"],
                "either",
                ["All hiders caught", "Time limit", "Either"],
            ),
            "time_limit": _int("Time limit", 5, 180, 30, step=5, suffix="min"),
        },
    },
    "hot_cold": {
        "version": 1,
        "title": "Hot / cold",
        "blurb": "Distance and direction toward hiders. Not a precise pin.",
        "field_order": ["enabled", "interval"],
        "fields": {
            "enabled": _bool("Hints", True),
            "interval": _int("Update every", 2, 30, 5, suffix="s"),
        },
    },
    "points": {
        "version": 1,
        "title": "Points",
        "blurb": "Scoring, including how often a hider can taunt.",
        "field_order": ["taunt_cooldown"],
        "fields": {
            "taunt_cooldown": _int("Taunt cooldown", 10, 180, 45, step=5, suffix="s"),
        },
    },
    "power_ups": {
        "version": 1,
        "title": "Power-ups",
        "blurb": "Purchases the dock already knows.",
        "field_order": ["enabled"],
        "fields": {"enabled": _bool("Enabled", True)},
    },
    "effects": {
        "version": 1,
        "title": "Effects",
        "blurb": "Timed effects. No host settings.",
        "field_order": [],
        "fields": {},
    },
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