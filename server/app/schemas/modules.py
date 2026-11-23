"""Versioned module settings schemas. Older versions migrate forward on load.

The iOS preset editor renders from this document (`GET /v1/modules`). Field order is
explicit because JSON objects do not define an order the client can rely on.
"""

from __future__ import annotations

from typing import Any

from app.engine.modules.power_ups import CATALOG
from app.limits import MAX_GAME_PLAYERS

_POWER_TITLES = {
    "ghost": "Ghost",
    "decoy": "Decoy",
    "radar": "Radar",
    "jammer": "Jammer",
    "shield": "Shield",
    "rescue": "Rescue",
    "create_safe": "Create safe",
    "scan": "Scan",
    "tracker": "Tracker",
    "lockdown": "Lockdown",
    "move_safe": "Move safe",
    "shrink_now": "Shrink now",
}


def _power_ups_fields() -> tuple[list[str], dict[str, Any]]:
    fields: dict[str, Any] = {"enabled": _bool("Enabled", True)}
    field_order = ["enabled"]
    for power_id, base in CATALOG.items():
        title = _POWER_TITLES[power_id]
        help_text = None
        if power_id == "tracker":
            help_text = (
                "Timed hot/cold for seekers. Unavailable when Location is Hot/cold "
                "or Location timing is Persistent."
            )
        elif power_id == "rescue":
            help_text = "Convert a tagged seeker back to hider with brief immunity."
        elif power_id == "shrink_now":
            help_text = "Fire the next zone shrink now and shift the remaining schedule."
        fields[f"{power_id}_enabled"] = _bool(title, True, help_text=help_text)
        fields[f"{power_id}_cost"] = _int(
            f"{title} cost", 0, 200, int(base["cost"]), step=5, suffix="pts"
        )
        field_order.extend([f"{power_id}_enabled", f"{power_id}_cost"])
        if power_id == "scan":
            fields["scan_radius_m"] = _int("Scan radius", 10, 150, 30, step=5, suffix="m")
            fields["scan_count"] = _int("Scan pins", 1, 5, 1)
            field_order.extend(["scan_radius_m", "scan_count"])
        elif power_id == "rescue":
            fields["rescue_duration"] = _int(
                "Rescue immunity", 15, 180, int(base["duration"]), step=15, suffix="s"
            )
            field_order.append("rescue_duration")
        elif power_id == "create_safe":
            fields["create_safe_radius_m"] = _int(
                "New safe radius", 10, 80, 30, step=5, suffix="m"
            )
            field_order.append("create_safe_radius_m")
    return field_order, fields


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


def _bool(title: str, default: bool, *, help_text: str | None = None) -> dict[str, Any]:
    field: dict[str, Any] = {"type": "bool", "title": title, "default": default}
    if help_text is not None:
        field["help"] = help_text
    return field


def _enum(
    title: str,
    values: list[str],
    default: str,
    labels: list[str] | None = None,
    *,
    help_text: str | None = None,
) -> dict[str, Any]:
    field: dict[str, Any] = {"type": "enum", "title": title, "values": values, "default": default}
    if labels is not None:
        field["labels"] = labels
    if help_text is not None:
        field["help"] = help_text
    return field


SCHEMAS: dict[str, dict[str, Any]] = {
    "roles": {
        "version": 1,
        "title": "Roles",
        "blurb": "How hiders and seekers are chosen in the lobby.",
        "field_order": ["mode", "seeker_count"],
        "fields": {
            "mode": _enum("Assignment", ["random", "manual"], "random", ["Random", "Manual"]),
            "seeker_count": _int("Seekers", 1, MAX_GAME_PLAYERS, 1),
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
        "title": "Reveal",
        "blurb": (
            "Location pulses and hot/cold hints. Hints: Fuzzy when Hints is on; "
            "always on in Hot/cold; off in Precise."
        ),
        "locked": True,
        "field_order": [
            "location_mode",
            "persistence",
            "interval",
            "display",
            "fuzz",
            "hints_enabled",
            "hints_persistence",
            "hints_interval",
        ],
        "fields": {
            "location_mode": _enum(
                "Location",
                ["fuzzy", "precise", "hot_cold"],
                "fuzzy",
                ["Fuzzy", "Precise", "Hot/cold"],
                help_text=(
                    "Fuzzy: offset pins, optional hints. Precise: true pins, no hints. "
                    "Hot/cold: distance and direction only (hints always on)."
                ),
            ),
            "persistence": _enum(
                "Location timing",
                ["timed", "persistent"],
                "timed",
                ["Timed", "Persistent"],
                help_text="Persistent pins never expire. Tracker is unavailable while Persistent.",
            ),
            "interval": _int("Every", 20, 600, 60, step=10, suffix="s"),
            "display": _int("Stays up", 5, 60, 10, step=5, suffix="s"),
            "fuzz": _int("Fuzz", 0, 100, 30, step=5, suffix="m"),
            "hints_enabled": _bool(
                "Hints",
                True,
                help_text=(
                    "Fuzzy only. On: seekers get hot/cold with pins. "
                    "Hot/cold mode always has hints; Precise never does."
                ),
            ),
            "hints_persistence": _enum(
                "Hints timing", ["timed", "persistent"], "persistent", ["Timed", "Persistent"]
            ),
            "hints_interval": _int("Hints every", 2, 30, 5, suffix="s"),
        },
    },
    "reveal_seekers": {
        "version": 1,
        "title": "Seeker reveal",
        "blurb": (
            "Hiders see seeker pulses. Off sends nothing. "
            "Fuzzy, Precise, and Hot/cold match Reveal."
        ),
        "locked": True,
        "field_order": [
            "location_mode",
            "persistence",
            "interval",
            "display",
            "fuzz",
            "hints_enabled",
            "hints_persistence",
            "hints_interval",
        ],
        "fields": {
            "location_mode": _enum(
                "Location",
                ["off", "fuzzy", "precise", "hot_cold"],
                "off",
                ["Off", "Fuzzy", "Precise", "Hot/cold"],
                help_text=(
                    "Off: hiders see no seeker pulses. "
                    "Fuzzy: offset pins, optional hints. Precise: true pins, no hints. "
                    "Hot/cold: distance and direction only (hints always on)."
                ),
            ),
            "persistence": _enum(
                "Location timing",
                ["timed", "persistent"],
                "timed",
                ["Timed", "Persistent"],
                help_text="Persistent pins never expire.",
            ),
            "interval": _int("Every", 20, 600, 60, step=10, suffix="s"),
            "display": _int("Stays up", 5, 60, 10, step=5, suffix="s"),
            "fuzz": _int("Fuzz", 0, 100, 30, step=5, suffix="m"),
            "hints_enabled": _bool(
                "Hints",
                True,
                help_text=(
                    "Fuzzy only. On: hiders get hot/cold with pins. "
                    "Hot/cold mode always has hints; Precise never does."
                ),
            ),
            "hints_persistence": _enum(
                "Hints timing", ["timed", "persistent"], "persistent", ["Timed", "Persistent"]
            ),
            "hints_interval": _int("Hints every", 2, 30, 5, suffix="s"),
        },
    },
    "tag_policy": {
        "version": 1,
        "title": "Tag",
        "blurb": "Seekers scan a rotating QR code. The code is the tag; GPS distance is not.",
        "locked": True,
        # Host editor hides this card. pairing_m stays in the snapshot for old clients
        # and is no longer consulted by check_tag.
        "hidden": True,
        "field_order": ["method", "radius_m", "result", "pairing_m"],
        "fields": {
            "method": _enum("Method", ["qr"], "qr", ["QR code"]),
            "radius_m": _number("Radius", 1, 5, 2, step=0.5, suffix="m"),
            "result": _enum(
                "Result",
                ["eliminate", "convert"],
                "eliminate",
                ["Eliminate", "Join seekers"],
            ),
            "pairing_m": _int("Pairing", 30, 30, 30, step=5, suffix="m"),
        },
    },
    "zone_policy": {
        "version": 1,
        "title": "Zones",
        "blurb": (
            "Out of bounds counts down. Safe visit and cooldown limit each stay; "
            "remove-after drops every safe zone from the hunt."
        ),
        "locked": True,
        "field_order": [
            "oob_countdown",
            "hider_oob_penalty",
            "safe_visit",
            "safe_cooldown",
            "safe_remove_after",
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
            "safe_remove_after": _int(
                "Remove safes after", 0, 180, 0, step=5, suffix="min"
            ),
            "margin_m": _int("Edge margin", 0, 30, 5, suffix="m"),
        },
    },
    "zone_shrink": {
        "version": 1,
        "title": "Zone shrink",
        "blurb": "Shrinks a circle play area on a timer. Disabled for polygon arenas.",
        "field_order": ["enabled", "every", "shrink_to", "min_radius_m"],
        "fields": {
            "enabled": _bool("Enabled", False),
            "every": _int("Every", 1, 30, 5, step=1, suffix="min"),
            "shrink_to": _int("Keep per shrink", 50, 95, 75, step=5, suffix="%"),
            "min_radius_m": _int("Minimum radius", 30, 500, 50, step=10, suffix="m"),
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
        "locked": True,
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
    "points": {
        "version": 1,
        "title": "Points",
        "blurb": "Scoring, including how often a hider can taunt.",
        "locked": True,
        "field_order": ["taunt_enabled", "taunt_cooldown"],
        "fields": {
            "taunt_enabled": _bool("Taunt", True),
            "taunt_cooldown": _int("Taunt cooldown", 10, 180, 45, step=5, suffix="s"),
        },
    },
    "power_ups": {
        "version": 1,
        "title": "Power-ups",
        "blurb": "Purchases the dock already knows.",
        "locked": False,
        **dict(
            zip(
                ("field_order", "fields"),
                _power_ups_fields(),
            )
        ),
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