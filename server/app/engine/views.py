"""Per-player filtered state. This is the anti-cheat boundary."""

from __future__ import annotations

from uuid import UUID

from app.engine.arena import ZoneKind, arena_to_dict
from app.engine.modules.head_start import spawn_clock_held
from app.engine.modules.zone_shrink import zone_shrink_schedule
from app.engine.session import GameSession
from app.engine.state import PlayerState


def build_view(
    session: GameSession,
    viewer_id: UUID,
    *,
    demo_controls_enabled: bool = True,
) -> dict:
    state = session.state
    viewer = state.players[viewer_id]
    players = []
    for player in state.players.values():
        players.append(
            {
                "player_id": str(player.player_id),
                "display_name": player.display_name,
                "role": player.role,
                "status": player.status,
                "is_host": player.is_host,
                "points": player.points,
                "points_earned": player.points_earned,
                "location": _visible_location(state, viewer, player),
            }
        )
    reveals = []
    for pin in state.reveals:
        if viewer.role == "seeker" or pin.player_id == viewer_id:
            player = state.players.get(pin.player_id)
            reveals.append(
                {
                    "reveal_id": str(pin.reveal_id),
                    "player_id": str(pin.player_id),
                    "lat": pin.lat,
                    "lon": pin.lon,
                    "radius_m": pin.radius_m,
                    "expires_in_s": max(0, pin.expires_at_game_s - state.game_elapsed_s),
                    "display_name": player.display_name if player is not None else "",
                }
            )
    you_safe = None
    if viewer.safe_zone_id is not None:
        you_safe = {
            "zone_id": str(viewer.safe_zone_id),
            "remaining_s": viewer.safe_remaining_s,
        }
    result = None
    if state.result is not None:
        result = {
            "winner": state.result.winner,
            "reason": state.result.reason,
            "ended_at": state.result.ended_at.isoformat() if state.result.ended_at else None,
        }
    seeker_lock, spawn_lock = _spawn_lock(session, viewer_id)
    now = state.game_elapsed_s
    taunt_ready = viewer.taunt_cooldown_until_s
    taunt_cooldown_s = max(0, taunt_ready - now) if taunt_ready is not None else 0
    cooldowns = {
        power_id: max(0, ready_at - now)
        for power_id, ready_at in viewer.cooldowns.items()
        if ready_at > now
    }
    return {
        "game_id": str(state.game_id),
        "join_code": state.join_code,
        "phase": state.phase,
        "tag_method": str(session.module_settings("tag_policy").get("method", "qr")),
        "seeker_lock": seeker_lock,
        "spawn_lock": spawn_lock,
        "phase_remaining_s": state.phase_remaining_s,
        "lobby_starts_in_s": state.lobby_starts_in_s,
        "game_elapsed_s": state.game_elapsed_s,
        "time_limit_remaining_s": state.time_limit_remaining_s,
        "timers": _build_timers(session),
        "you": {
            "player_id": str(viewer.player_id),
            "role": viewer.role,
            "status": viewer.status,
            "is_host": viewer.is_host,
            "bounds": {
                "phase": viewer.bounds_phase,
                "remaining_s": viewer.bounds_remaining_s,
            },
            "safe_zone": you_safe,
            "points": viewer.points,
            "points_earned": viewer.points_earned,
            "hint": viewer.hint,
            "effects": [e.type for e in state.effects if e.owner_id == viewer.player_id],
            "cooldowns": cooldowns,
            "taunt_cooldown_s": taunt_cooldown_s,
            "taunt_enabled": bool(session.module_settings("points").get("taunt_enabled", True)),
        },
        "arena": arena_to_dict(state.arena),
        "players": players,
        "reveals": reveals,
        "banners": [
            {
                "banner_id": str(b.banner_id),
                "tone": b.tone,
                "title": b.title,
                "detail": b.detail,
                "player_id": str(b.player_id) if b.player_id else None,
            }
            for b in state.banners
        ],
        "result": result,
        "power_ups": _power_ups_for(session, viewer),
        "demo": _build_demo(session, viewer, demo_controls_enabled=demo_controls_enabled),
    }


def _power_ups_for(session: GameSession, viewer: PlayerState) -> list[dict]:
    from app.engine.modules.power_ups import CATALOG

    settings = session.module_settings("power_ups")
    if not bool(settings.get("enabled", True)):
        return []
    titles = {
        "ghost": "Ghost",
        "decoy": "Decoy",
        "radar": "Radar",
        "jammer": "Jammer",
        "shield": "Shield",
        "scan": "Scan",
        "tracker": "Tracker",
        "lockdown": "Lockdown",
    }
    rows = []
    for power_id, base in CATALOG.items():
        if base["role"] != viewer.role:
            continue
        if not bool(settings.get(f"{power_id}_enabled", True)):
            continue
        rows.append(
            {
                "id": power_id,
                "title": titles[power_id],
                "cost": int(settings.get(f"{power_id}_cost", base["cost"])),
                "role": base["role"],
            }
        )
    return rows


def _build_demo(
    session: GameSession,
    viewer: PlayerState,
    *,
    demo_controls_enabled: bool,
) -> dict | None:
    demo = session.demo
    if demo is None:
        return None
    bots = []
    for bot_id in demo.bot_ids:
        bot = session.state.players.get(bot_id)
        if bot is None:
            continue
        bots.append(
            {
                "player_id": str(bot.player_id),
                "display_name": bot.display_name,
                "role": bot.role,
                "status": bot.status,
                "mode": demo.bot_modes.get(bot_id, "auto"),
            }
        )
    vloc = viewer.location
    return {
        "speed": demo.speed,
        "lobby_hold": demo.lobby_hold,
        "seeker_lock": str(session.module_settings("head_start").get("seeker_lock", "locked_map")),
        "controls_enabled": bool(demo_controls_enabled and viewer.is_host),
        "virtual_location": {"lat": vloc.lat, "lon": vloc.lon} if vloc is not None else None,
        "bots": bots,
    }


def _visible_location(state, viewer: PlayerState, other: PlayerState) -> dict | None:
    if state.phase == "lobby":
        return None
    loc = other.last_precise or other.location
    if loc is None:
        return None

    def pack(kind: str) -> dict:
        return {
            "lat": loc.lat,
            "lon": loc.lon,
            "accuracy_m": loc.accuracy_m,
            "at": loc.recorded_at.isoformat(),
            "kind": kind,
        }

    if other.player_id == viewer.player_id:
        return pack("exact")
    if state.phase == "ended":
        return pack("last_known" if other.status == "signal_lost" else "exact")
    if other.status == "signal_lost":
        return pack("last_known")
    if other.role == viewer.role and other.role != "unassigned":
        return pack("exact")
    # Seeker out of bounds is shown to everyone, including hiders.
    if other.role == "seeker" and other.oob_revealed:
        return pack("exact")
    now = state.game_elapsed_s
    if (
        viewer.role == "hider"
        and other.role == "seeker"
        and viewer.radar_until_s is not None
        and viewer.radar_until_s > now
    ):
        return pack("exact")
    if other.role == "hider" and other.taunt_until_s is not None and other.taunt_until_s > now:
        return pack("exact")
    return None


def _spawn_lock(session: GameSession, viewer_id: UUID) -> tuple[str | None, dict | None]:
    """Spawn geometry rides on the view so a joiner does not need a local arena copy."""
    state = session.state
    if state.phase != "head_start":
        return None, None
    seeker_lock = str(session.module_settings("head_start").get("seeker_lock", "locked_map"))
    if seeker_lock != "spawn_zone":
        return seeker_lock, None
    outside = any(
        banner.player_id == viewer_id and banner.title == "Stay in spawn"
        for banner in state.banners
    )
    zones = [
        zone
        for zone in arena_to_dict(state.arena)["zones"]
        if zone["kind"] == ZoneKind.SEEKER_SPAWN
    ]
    return seeker_lock, {
        "outside": outside,
        "zones": zones,
        "holding": spawn_clock_held(session),
    }


def _build_timers(session: GameSession) -> dict:
    state = session.state
    head_start = session.module_settings("head_start")
    head_start_enabled = bool(head_start.get("enabled", True))
    head_start_s = int(head_start.get("duration", 60)) if head_start_enabled else 0
    win = session.module_settings("win")
    time_limit_s = int(win.get("time_limit", 30)) * 60
    reveal = session.module_settings("reveal_fuzzy")
    reveal_enabled = bool(reveal.get("enabled", True))
    reveal_interval_s = int(reveal.get("interval", 60)) if reveal_enabled else None
    next_reveal_in_s: int | None = None
    if reveal_interval_s is not None and state.phase != "ended":
        if state.phase == "lobby":
            next_reveal_in_s = reveal_interval_s
        else:
            next_at = (
                reveal_interval_s
                if state.last_reveal_at_s is None
                else state.last_reveal_at_s + reveal_interval_s
            )
            next_reveal_in_s = max(0, next_at - state.game_elapsed_s)
    zone_timer = None
    if (schedule := zone_shrink_schedule(session)) is not None:
        zone_timer = {
            "radius_m": schedule["current_radius_m"],
            "next_radius_m": schedule["next_radius_m"],
            "shrinks_in_s": schedule["shrinks_in_s"],
        }
    return {
        "head_start_s": head_start_s,
        "time_limit_s": time_limit_s,
        "reveal_interval_s": reveal_interval_s,
        "next_reveal_in_s": next_reveal_in_s,
        "zone": zone_timer,
    }

