"""Host and virtual-player control actions for PARK42 demo sessions."""

from __future__ import annotations

import math
from datetime import timedelta
from typing import Any
from uuid import UUID

from app.demo.bots import BotDriver, _arena_center, _in_play, _step_toward, _zone_center
from app.demo.state import ALLOWED_SPEEDS, DemoState
from app.engine.arena import ZoneKind
from app.engine.geo import GeoPoint, distance_m, offset_m
from app.engine.modules.base import TagClaim
from app.engine.modules.reveal_fuzzy import RevealFuzzyModule
from app.engine.modules.signal_loss import SignalLossModule
from app.engine.modules.zone_policy import ZonePolicyModule
from app.engine.qr import make_qr_token, token_ttl
from app.engine.session import GameSession
from app.engine.state import LocationReading
from app.errors import ErrorCode, GameRuleError


def apply_demo_action(
    session: GameSession,
    actor_id: UUID,
    action: str,
    params: dict[str, Any],
) -> None:
    demo = session.demo
    if demo is None:
        raise GameRuleError(ErrorCode.GAME_NOT_FOUND, "Not a demo session.")

    if action == "set_speed":
        _set_speed(demo, params.get("speed"))
    elif action == "skip":
        _skip(session, int(params.get("seconds", 60)))
    elif action == "force_tag":
        raw_hid = params.get("hider_id")
        hider_id = UUID(str(raw_hid)) if raw_hid else None
        _force_tag(session, actor_id, hider_id)
    elif action == "switch_team":
        raw_role = params.get("role")
        role = str(raw_role) if raw_role is not None else None
        _switch_team(session, actor_id, role)
    elif action == "end_phase":
        _end_phase(session)
    elif action == "force_reveal":
        _force_reveal(session)
    elif action == "add_points":
        _add_points(session, actor_id, int(params.get("amount", 100)))
    elif action == "bot_go_dark":
        raw_bid = params.get("bot_id")
        bot_id = UUID(str(raw_bid)) if raw_bid else None
        dark = bool(params.get("dark", True))
        _bot_go_dark(session, demo, bot_id, dark=dark)
    elif action == "bot_oob":
        raw_bid = params.get("bot_id")
        bot_id = UUID(str(raw_bid)) if raw_bid else None
        oob = bool(params.get("oob", True))
        _bot_oob(session, demo, bot_id, oob=oob)
    elif action == "move_me":
        _move_me(session, demo, actor_id, params.get("lat"), params.get("lon"))
    elif action == "lobby_hold":
        _lobby_hold(session, demo, bool(params.get("hold", True)))
    elif action == "set_seeker_lock":
        _set_seeker_lock(session, str(params.get("mode", "")))
    else:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, f"Unknown demo action {action}.")


def _set_speed(demo: DemoState, raw_speed: Any) -> None:
    try:
        speed = int(raw_speed)
    except (TypeError, ValueError) as exc:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Speed must be an integer.") from exc
    if speed not in ALLOWED_SPEEDS:
        raise GameRuleError(
            ErrorCode.VALIDATION_FAILED,
            f"Speed must be one of {ALLOWED_SPEEDS}.",
        )
    demo.speed = speed


def _skip(session: GameSession, seconds: int) -> None:
    if seconds < 1 or seconds > 600:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Skip must be between 1 and 600s.")
    if session.state.phase not in {"head_start", "active"}:
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Skip is only available during a live hunt.")
    for _ in range(seconds):
        if session.state.phase not in {"head_start", "active"}:
            break
        session.tick()
        BotDriver.step(session)


def _force_tag(session: GameSession, actor_id: UUID, hider_id: UUID | None) -> None:
    if session.state.phase != "active":
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Force tag requires the active hunt phase.")
    hiders = [
        p
        for p in session.state.players.values()
        if p.role == "hider" and p.status == "active"
    ]
    if hider_id is not None:
        target = next((p for p in hiders if p.player_id == hider_id), None)
    else:
        target = next((p for p in hiders if p.player_id == actor_id), None) or (
            hiders[0] if hiders else None
        )
    if target is None:
        raise GameRuleError(ErrorCode.TARGET_NOT_ACTIVE, "No active hider to tag.")

    seekers = [
        p
        for p in session.state.players.values()
        if p.role == "seeker" and p.player_id != target.player_id
    ]
    if not seekers:
        raise GameRuleError(ErrorCode.NEED_BOTH_ROLES, "Need at least one seeker to tag.")
    demo = session.demo
    bot_seekers = [s for s in seekers if demo is not None and demo.is_bot(s.player_id)]
    seeker = bot_seekers[0] if bot_seekers else seekers[0]

    center = _arena_center(session.state.arena)
    hider_pt = target.location.point if target.location is not None else center
    if target.location is None:
        session.set_synthetic_location(
            target.player_id,
            LocationReading(
                lat=hider_pt.lat, lon=hider_pt.lon, accuracy_m=5.0, recorded_at=session.clock.now()
            ),
        )
    near_pt = offset_m(hider_pt, north_m=0.5, east_m=0.0)
    if not _in_play(near_pt, session.state.arena):
        near_pt = hider_pt
    session.set_synthetic_location(
        seeker.player_id,
        LocationReading(
            lat=near_pt.lat, lon=near_pt.lon, accuracy_m=5.0, recorded_at=session.clock.now()
        ),
    )

    method = str(session.module_settings("tag_policy").get("method", "qr"))
    if method == "qr":
        token = make_qr_token(
            game_id=session.state.game_id,
            hider_id=target.player_id,
            expires_at=session.clock.now() + token_ttl(),
            key=session.qr_signing_key,
        )
        claim = TagClaim(seeker.player_id, target.player_id, qr_token=token)
    else:
        claim = TagClaim(seeker.player_id, target.player_id, seeker_range=0.5, hider_range=0.5)
    session.claim_tag(claim)
    if demo is not None:
        demo.last_bot_tag_s = session.state.game_elapsed_s


def _switch_team(session: GameSession, actor_id: UUID, role: str | None) -> None:
    if session.state.phase == "ended":
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Game has already ended.")
    player = session.state.players.get(actor_id)
    if player is None:
        raise GameRuleError(ErrorCode.NOT_A_MEMBER)
    if role is None:
        next_role = "seeker" if player.role == "hider" else "hider"
    else:
        if role not in {"hider", "seeker"}:
            raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Role must be hider or seeker.")
        next_role = role

    session.set_role(actor_id, next_role)
    player.status = "active"
    player.safe_zone_id = None
    player.safe_remaining_s = None
    player.safe_expired = False
    player.bounds_phase = "inside"
    player.bounds_remaining_s = None
    player.oob_revealed = False

    if session.state.phase == "head_start" and next_role == "seeker":
        spawn = next(
            (z for z in session.state.arena.zones if z.kind == ZoneKind.SEEKER_SPAWN), None
        )
        if spawn is not None:
            pt = _zone_center(spawn)
            session.set_synthetic_location(
                actor_id,
                LocationReading(
                    lat=pt.lat, lon=pt.lon, accuracy_m=5.0, recorded_at=session.clock.now()
                ),
            )
    session._check_win()


def _end_phase(session: GameSession) -> None:
    phase = session.state.phase
    if phase == "lobby":
        session.sample_start_after_s = None
        session.state.lobby_starts_in_s = None
        session.start()
        return
    if phase == "head_start":
        for _ in range(605):
            if session.state.phase != "head_start":
                break
            session.tick()
            BotDriver.step(session)
        return
    if phase in {"active", "paused"}:
        session.end("Host ended the demo.", winner="none")
        return
    raise GameRuleError(ErrorCode.WRONG_PHASE, "Game has already ended.")


def _force_reveal(session: GameSession) -> None:
    if session.state.phase not in {"head_start", "active"}:
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Reveal requires a live hunt.")
    reveal_mod = next((m for m in session.modules if isinstance(m, RevealFuzzyModule)), None)
    if reveal_mod is None or not bool(reveal_mod.settings.get("enabled", True)):
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Fuzzy reveals are disabled.")
    interval = max(1, int(reveal_mod.settings.get("interval", 60)))
    session.state.last_reveal_at_s = session.state.game_elapsed_s - interval
    reveal_mod.on_tick(session)


def _add_points(session: GameSession, actor_id: UUID, amount: int) -> None:
    if amount < 1 or amount > 1000:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Points must be between 1 and 1000.")
    player = session.state.players.get(actor_id)
    if player is None:
        raise GameRuleError(ErrorCode.NOT_A_MEMBER)
    player.points += amount


def _pick_bot(
    session: GameSession,
    demo: DemoState,
    bot_id: UUID | None,
    *,
    predicate,
) -> UUID:
    if bot_id is not None:
        if not demo.is_bot(bot_id) or bot_id not in session.state.players:
            raise GameRuleError(ErrorCode.TARGET_NOT_ACTIVE, "Bot not found.")
        return bot_id
    for candidate_id in demo.bot_ids:
        player = session.state.players.get(candidate_id)
        if player is None or player.status == "eliminated":
            continue
        if predicate(candidate_id, player):
            return candidate_id
    raise GameRuleError(ErrorCode.TARGET_NOT_ACTIVE, "No eligible bot available.")


def _bot_go_dark(
    session: GameSession,
    demo: DemoState,
    bot_id: UUID | None,
    *,
    dark: bool,
) -> None:
    chosen = _pick_bot(
        session,
        demo,
        bot_id,
        predicate=lambda bid, p: (
            demo.bot_modes.get(bid) != "go_dark"
            if dark
            else (demo.bot_modes.get(bid) == "go_dark" or p.status == "signal_lost")
        ),
    )
    bot = session.state.players[chosen]
    signal_mod = next((m for m in session.modules if isinstance(m, SignalLossModule)), None)
    silence = int(signal_mod.settings.get("silence", 45)) if signal_mod else 45
    if dark:
        demo.bot_modes[chosen] = "go_dark"
        bot.last_location_at = session.clock.now() - timedelta(seconds=silence + 5)
    else:
        demo.bot_modes[chosen] = "auto"
        center = _arena_center(session.state.arena)
        pt = bot.location.point if bot.location is not None else center
        session.set_synthetic_location(
            chosen,
            LocationReading(
                lat=pt.lat, lon=pt.lon, accuracy_m=5.0, recorded_at=session.clock.now()
            ),
        )
    if signal_mod is not None and session.state.phase in {"head_start", "active", "paused"}:
        signal_mod.on_tick(session)


def _bot_oob(
    session: GameSession,
    demo: DemoState,
    bot_id: UUID | None,
    *,
    oob: bool,
) -> None:
    chosen = _pick_bot(
        session,
        demo,
        bot_id,
        predicate=lambda bid, _p: (
            demo.bot_modes.get(bid) != "oob" if oob else demo.bot_modes.get(bid) == "oob"
        ),
    )
    center = _arena_center(session.state.arena)
    radius = (
        session.state.arena.boundary_circle.radius_m
        if session.state.arena.boundary_circle is not None
        else 150.0
    )
    if oob:
        demo.bot_modes[chosen] = "oob"
        pt = offset_m(center, north_m=0.0, east_m=radius + 20.0)
    else:
        demo.bot_modes[chosen] = "auto"
        pt = offset_m(center, north_m=0.0, east_m=min(30.0, radius * 0.4))
    session.set_synthetic_location(
        chosen,
        LocationReading(lat=pt.lat, lon=pt.lon, accuracy_m=5.0, recorded_at=session.clock.now()),
    )
    zone_mod = next((m for m in session.modules if isinstance(m, ZonePolicyModule)), None)
    if zone_mod is not None and session.state.phase in {"head_start", "active"}:
        zone_mod.on_tick(session)


def _move_me(
    session: GameSession,
    demo: DemoState,
    actor_id: UUID,
    raw_lat: Any,
    raw_lon: Any,
) -> None:
    try:
        lat = float(raw_lat)
        lon = float(raw_lon)
    except (TypeError, ValueError) as exc:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "lat and lon are required.") from exc
    valid = (
        math.isfinite(lat)
        and math.isfinite(lon)
        and -90.0 <= lat <= 90.0
        and -180.0 <= lon <= 180.0
    )
    if not valid:
        raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Invalid coordinates.")

    target = GeoPoint(lat=lat, lon=lon)
    center = _arena_center(session.state.arena)
    if distance_m(center, target) > 5000.0:
        raise GameRuleError(ErrorCode.TARGET_OUTSIDE, "Target is too far from the sample park.")

    player = session.state.players.get(actor_id)
    if player is None:
        raise GameRuleError(ErrorCode.NOT_A_MEMBER)
    current = player.location.point if player.location is not None else center
    next_pt = _step_toward(current, target, demo.walk_speed_mps)
    if distance_m(next_pt, target) < 0.5:
        demo.human_targets.pop(actor_id, None)
        next_pt = target
    else:
        demo.human_targets[actor_id] = target
    session.set_synthetic_location(
        actor_id,
        LocationReading(
            lat=next_pt.lat,
            lon=next_pt.lon,
            accuracy_m=5.0,
            recorded_at=session.clock.now(),
        ),
    )


def _lobby_hold(session: GameSession, demo: DemoState, hold: bool) -> None:
    if session.state.phase != "lobby":
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Lobby hold only applies in the lobby.")
    demo.lobby_hold = hold


def _set_seeker_lock(session: GameSession, mode: str) -> None:
    if session.state.phase != "lobby":
        raise GameRuleError(ErrorCode.WRONG_PHASE, "Seeker lock can only be changed in the lobby.")
    if mode not in {"spawn_zone", "locked_map"}:
        raise GameRuleError(
            ErrorCode.VALIDATION_FAILED,
            "Seeker lock must be spawn_zone or locked_map.",
        )
    modules = session.state.preset.setdefault("modules", {})
    head_start = modules.setdefault("head_start", {})
    head_start["seeker_lock"] = mode
