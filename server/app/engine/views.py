"""Per-player filtered state. This is the anti-cheat boundary."""

from __future__ import annotations

from uuid import UUID

from app.engine.arena import ZoneKind, arena_to_dict
from app.engine.session import GameSession
from app.engine.state import PlayerState


def build_view(session: GameSession, viewer_id: UUID) -> dict:
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
                "location": _visible_location(state, viewer, player),
            }
        )
    reveals = []
    for pin in state.reveals:
        if viewer.role == "seeker" or pin.player_id == viewer_id:
            reveals.append(
                {
                    "reveal_id": str(pin.reveal_id),
                    "player_id": str(pin.player_id),
                    "lat": pin.lat,
                    "lon": pin.lon,
                    "radius_m": pin.radius_m,
                    "expires_in_s": max(0, pin.expires_at_game_s - state.game_elapsed_s),
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
            "hint": viewer.hint,
            "effects": [e.type for e in state.effects if e.owner_id == viewer.player_id],
            "cooldowns": cooldowns,
            "taunt_cooldown_s": taunt_cooldown_s,
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
    return seeker_lock, {"outside": outside, "zones": zones}
