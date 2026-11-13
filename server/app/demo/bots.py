"""Server-side bot AI driver for demo sessions."""

from __future__ import annotations

import math
from typing import TYPE_CHECKING

from app.engine.arena import Arena, ArenaZone, CircleShape, ZoneKind
from app.engine.geo import (
    METERS_PER_DEGREE,
    GeoPoint,
    circle_covers,
    contains,
    distance_m,
    distance_outside_m,
    distance_outside_to_interior_edge,
    offset_m,
)
from app.engine.modules.base import TagClaim
from app.engine.modules.zone_shrink import zone_shrink_schedule
from app.engine.qr import make_qr_token, token_ttl
from app.engine.state import LocationReading, PlayerState
from app.errors import GameRuleError

if TYPE_CHECKING:
    from app.demo.state import DemoState
    from app.engine.session import GameSession

_TWO_PI = 2.0 * math.pi
_EDGE_BUFFER_M = 12.0
_CHASE_VISION_M = 65.0
_FLEE_VISION_M = 70.0
_HEAD_START_TAG_GRACE_S = 4
_BOT_TAG_COOLDOWN_S = 6


def _arena_center(arena: Arena) -> GeoPoint:
    if arena.boundary_circle is not None:
        return arena.boundary_circle.center
    boundary = arena.boundary
    lat = sum(p.lat for p in boundary) / max(1, len(boundary))
    lon = sum(p.lon for p in boundary) / max(1, len(boundary))
    return GeoPoint(lat=lat, lon=lon)


def _zone_center(zone: ArenaZone) -> GeoPoint:
    if isinstance(zone.shape, CircleShape):
        return zone.shape.center
    verts = zone.shape.vertices
    lat = sum(p.lat for p in verts) / max(1, len(verts))
    lon = sum(p.lon for p in verts) / max(1, len(verts))
    return GeoPoint(lat=lat, lon=lon)


def _in_zone(point: GeoPoint, zone: ArenaZone) -> bool:
    if isinstance(zone.shape, CircleShape):
        return circle_covers(zone.shape.center, zone.shape.radius_m, point)
    return contains(point, zone.shape.vertices)


def _in_play(point: GeoPoint, arena: Arena) -> bool:
    if not contains(point, arena.boundary):
        return False
    for zone in arena.zones:
        if zone.kind == ZoneKind.OUT_OF_BOUNDS and _in_zone(point, zone):
            return False
    return True


def _east_north(origin: GeoPoint, target: GeoPoint) -> tuple[float, float]:
    lat0 = math.radians((origin.lat + target.lat) / 2.0)
    north = (target.lat - origin.lat) * METERS_PER_DEGREE
    east = (target.lon - origin.lon) * METERS_PER_DEGREE * math.cos(lat0)
    return east, north


def _heading_toward(origin: GeoPoint, target: GeoPoint) -> float:
    east, north = _east_north(origin, target)
    return math.atan2(east, north)


def _step_heading(origin: GeoPoint, heading_rad: float, meters: float) -> GeoPoint:
    return offset_m(
        origin,
        north_m=meters * math.cos(heading_rad),
        east_m=meters * math.sin(heading_rad),
    )


def _step_toward(origin: GeoPoint, target: GeoPoint, max_step_m: float) -> GeoPoint:
    dist = distance_m(origin, target)
    if dist <= max_step_m or dist <= 1e-6:
        return target
    return _step_heading(origin, _heading_toward(origin, target), max_step_m)


def _spawn_zone(arena: Arena) -> ArenaZone | None:
    for zone in arena.zones:
        if zone.kind == ZoneKind.SEEKER_SPAWN:
            return zone
    return None


def _move_inside(
    origin: GeoPoint,
    desired_heading: float,
    speed_mps: float,
    arena: Arena,
    demo: DemoState,
    *,
    max_radius_m: float | None = None,
) -> tuple[GeoPoint, float]:
    center = _arena_center(arena)
    in_bounds = _in_play(origin, arena)
    edge_dist = distance_outside_to_interior_edge(origin, arena.boundary) if in_bounds else 0.0

    if not in_bounds:
        to_center = _heading_toward(origin, center)
        candidate = _step_heading(origin, to_center, max(speed_mps, 12.0))
        return candidate, to_center

    if edge_dist < _EDGE_BUFFER_M or (
        max_radius_m is not None and distance_m(origin, center) > max_radius_m
    ):
        to_center = _heading_toward(origin, center)
        candidate = _step_heading(origin, to_center, max(speed_mps, 5.0))
        if _in_play(candidate, arena):
            return candidate, to_center

    candidate = _step_heading(origin, desired_heading, speed_mps)
    if _in_play(candidate, arena) and distance_outside_to_interior_edge(
        candidate, arena.boundary
    ) >= max(4.0, _EDGE_BUFFER_M * 0.5):
        return candidate, desired_heading

    # Probe nearby angles, then fall back toward center.
    to_center = _heading_toward(origin, center)
    for offset_deg in (45, -45, 90, -90, 135, -135):
        alt = desired_heading + math.radians(offset_deg)
        probe = _step_heading(origin, alt, speed_mps)
        if _in_play(probe, arena):
            return probe, alt

    fallback = _step_toward(origin, center, speed_mps)
    if _in_play(fallback, arena):
        return fallback, to_center
    jitter = demo.rng.random() * _TWO_PI
    return origin, jitter


def _reading(point: GeoPoint, session: GameSession) -> LocationReading:
    return LocationReading(
        lat=point.lat,
        lon=point.lon,
        accuracy_m=5.0,
        recorded_at=session.clock.now(),
    )


class BotDriver:
    @staticmethod
    def seed_positions(session: GameSession) -> None:
        """Place players inside the sample arena before the first tick."""
        arena = session.state.arena
        center = _arena_center(arena)
        spawn = _spawn_zone(arena)
        spawn_pt = _zone_center(spawn) if spawn is not None else center
        radius = arena.boundary_circle.radius_m if arena.boundary_circle else 140.0
        hider_ring_m = max(35.0, min(90.0, radius * 0.45))

        hiders = [
            p for p in session.state.players.values() if p.role == "hider" and p.location is None
        ]
        for idx, player in enumerate(hiders):
            angle = (idx / max(1, len(hiders))) * _TWO_PI + 0.3
            candidate = _step_heading(center, angle, hider_ring_m)
            if not _in_play(candidate, arena):
                candidate = center
            session.set_synthetic_location(player.player_id, _reading(candidate, session))

        for idx, player in enumerate(session.state.players.values()):
            if player.location is not None:
                continue
            if player.role == "seeker" and spawn is not None:
                pt = _step_heading(spawn_pt, (idx * 1.7) % _TWO_PI, 3.0)
                if not _in_zone(pt, spawn):
                    pt = spawn_pt
            else:
                pt = _step_heading(center, (idx * 1.3) % _TWO_PI, 8.0)
                if not _in_play(pt, arena):
                    pt = center
            session.set_synthetic_location(player.player_id, _reading(pt, session))

    @staticmethod
    def step(session: GameSession) -> None:
        """Advance virtual humans and bots for one engine tick."""
        demo = session.demo
        if demo is None:
            return
        if session.state.phase not in {"head_start", "active"}:
            return

        if session.state.phase == "active" and demo.head_start_ended_at_s is None:
            demo.head_start_ended_at_s = session.state.game_elapsed_s

        arena = session.state.arena
        center = _arena_center(arena)

        # Advance virtual human targets (and keep idle humans fresh so they don't go dark).
        for player in list(session.state.players.values()):
            if demo.is_bot(player.player_id) or player.status == "eliminated":
                continue
            current = player.location.point if player.location is not None else center
            target = demo.human_targets.get(player.player_id)
            if target is not None:
                next_pt = _step_toward(current, target, demo.walk_speed_mps)
                if distance_m(next_pt, target) < 0.5:
                    demo.human_targets.pop(player.player_id, None)
                    next_pt = target
                session.set_synthetic_location(player.player_id, _reading(next_pt, session))
            elif player.status != "signal_lost":
                session.set_synthetic_location(player.player_id, _reading(current, session))

        # Advance bots in deterministic order.
        for bot_id in demo.bot_ids:
            bot = session.state.players.get(bot_id)
            if bot is None or bot.status == "eliminated":
                continue
            mode = demo.bot_modes.get(bot_id, "auto")
            if mode == "go_dark":
                continue
            current = bot.location.point if bot.location is not None else center
            if mode == "oob":
                BotDriver._step_oob(session, bot, current, center)
                continue
            if session.state.phase == "head_start":
                BotDriver._step_head_start(session, demo, bot, current)
            else:
                BotDriver._step_active(session, demo, bot, current)

    @staticmethod
    def _step_oob(
        session: GameSession,
        bot: PlayerState,
        current: GeoPoint,
        center: GeoPoint,
    ) -> None:
        arena = session.state.arena
        out_dist = distance_outside_m(current, arena.boundary)
        if not contains(current, arena.boundary) and out_dist >= 18.0:
            session.set_synthetic_location(bot.player_id, _reading(current, session))
            return
        outward = _heading_toward(center, current) if distance_m(center, current) > 1.0 else 0.0
        next_pt = _step_heading(current, outward, 14.0)
        session.set_synthetic_location(bot.player_id, _reading(next_pt, session))

    @staticmethod
    def _step_head_start(
        session: GameSession,
        demo: DemoState,
        bot: PlayerState,
        current: GeoPoint,
    ) -> None:
        arena = session.state.arena
        spawn = _spawn_zone(arena)
        heading = demo.bot_headings.get(bot.player_id, 0.0)
        if bot.role == "seeker":
            if spawn is not None:
                spawn_pt = _zone_center(spawn)
                if not _in_zone(current, spawn):
                    next_pt = _step_toward(current, spawn_pt, 4.0)
                    session.set_synthetic_location(bot.player_id, _reading(next_pt, session))
                    return
                jitter = (heading + demo.rng.uniform(-0.7, 0.7)) % _TWO_PI
                probe = _step_heading(current, jitter, 1.8)
                next_pt = probe if _in_zone(probe, spawn) else _step_toward(current, spawn_pt, 1.5)
                demo.bot_headings[bot.player_id] = jitter
                session.set_synthetic_location(bot.player_id, _reading(next_pt, session))
                return
            next_pt, new_h = _move_inside(current, heading, 1.5, arena, demo)
            demo.bot_headings[bot.player_id] = new_h
            session.set_synthetic_location(bot.player_id, _reading(next_pt, session))
            return

        # Hiders spread away from spawn during head start.
        desired = (heading + demo.rng.uniform(-0.4, 0.4)) % _TWO_PI
        if spawn is not None:
            spawn_pt = _zone_center(spawn)
            if distance_m(current, spawn_pt) < 45.0:
                desired = _heading_toward(spawn_pt, current)
        next_pt, new_h = _move_inside(current, desired, 3.2, arena, demo)
        demo.bot_headings[bot.player_id] = new_h
        session.set_synthetic_location(bot.player_id, _reading(next_pt, session))

    @staticmethod
    def _step_active(
        session: GameSession,
        demo: DemoState,
        bot: PlayerState,
        current: GeoPoint,
    ) -> None:
        arena = session.state.arena
        heading = demo.bot_headings.get(bot.player_id, 0.0)
        shrink_cap: float | None = None
        schedule = zone_shrink_schedule(session)
        if schedule is not None:
            shrinks_in = schedule.get("shrinks_in_s")
            next_r = schedule.get("next_radius_m")
            if shrinks_in is not None and next_r is not None and shrinks_in <= 25:
                shrink_cap = max(10.0, float(next_r) - 12.0)

        if bot.role == "hider":
            nearest_seeker = _nearest_player(
                session,
                origin=current,
                role="seeker",
                max_dist_m=_FLEE_VISION_M,
            )
            if nearest_seeker is not None and nearest_seeker.location is not None:
                flee_heading = _heading_toward(nearest_seeker.location.point, current)
                desired = flee_heading + demo.rng.uniform(-0.25, 0.25)
                speed = 3.0
            else:
                desired = heading + demo.rng.uniform(-0.45, 0.45)
                speed = 2.6
            next_pt, new_h = _move_inside(
                current, desired % _TWO_PI, speed, arena, demo, max_radius_m=shrink_cap
            )
            demo.bot_headings[bot.player_id] = new_h
            session.set_synthetic_location(bot.player_id, _reading(next_pt, session))
            return

        if bot.role == "seeker":
            backoff_until = demo.bot_backoff_until_s.get(bot.player_id, 0)
            target_pt: GeoPoint | None = None
            target_hider: PlayerState | None = None
            if session.state.game_elapsed_s >= backoff_until:
                target_hider = _pick_chase_hider(session, current)
                if target_hider is not None and target_hider.location is not None:
                    target_pt = target_hider.location.point
                elif session.state.reveals:
                    target_pt = _nearest_reveal_point(session, current)

            if target_pt is not None:
                desired = _heading_toward(current, target_pt)
                speed = 4.8
                # Snap directly if within one step of a chase target so tags trigger cleanly.
                if target_hider is not None and distance_m(current, target_pt) <= speed:
                    step_dist = max(0.0, distance_m(current, target_pt) - 0.5)
                    next_pt = _step_toward(current, target_pt, step_dist)
                    if not _in_play(next_pt, arena):
                        next_pt, desired = _move_inside(
                            current, desired, speed, arena, demo, max_radius_m=shrink_cap
                        )
                else:
                    next_pt, desired = _move_inside(
                        current, desired, speed, arena, demo, max_radius_m=shrink_cap
                    )
            else:
                desired = (heading + demo.rng.uniform(-0.45, 0.45)) % _TWO_PI
                next_pt, desired = _move_inside(
                    current, desired, 3.4, arena, demo, max_radius_m=shrink_cap
                )

            demo.bot_headings[bot.player_id] = desired
            session.set_synthetic_location(bot.player_id, _reading(next_pt, session))
            BotDriver._maybe_tag(session, demo, bot, next_pt)
            return

        next_pt, new_h = _move_inside(
            current, heading, 2.0, arena, demo, max_radius_m=shrink_cap
        )
        demo.bot_headings[bot.player_id] = new_h
        session.set_synthetic_location(bot.player_id, _reading(next_pt, session))

    @staticmethod
    def _maybe_tag(
        session: GameSession,
        demo: DemoState,
        seeker: PlayerState,
        seeker_pt: GeoPoint,
    ) -> None:
        now_s = session.state.game_elapsed_s
        if demo.head_start_ended_at_s is not None:
            if now_s - demo.head_start_ended_at_s < _HEAD_START_TAG_GRACE_S:
                return
        if demo.last_bot_tag_s is not None and now_s - demo.last_bot_tag_s < _BOT_TAG_COOLDOWN_S:
            return
        if now_s < demo.bot_backoff_until_s.get(seeker.player_id, 0):
            return

        radius_m = float(session.module_settings("tag_policy").get("radius_m", 2.0))
        candidate = _nearest_player(
            session,
            origin=seeker_pt,
            role="hider",
            max_dist_m=radius_m,
            active_only=True,
        )
        if candidate is None:
            return

        method = str(session.module_settings("tag_policy").get("method", "qr"))
        if method == "qr":
            token = make_qr_token(
                game_id=session.state.game_id,
                hider_id=candidate.player_id,
                expires_at=session.clock.now() + token_ttl(),
                key=session.qr_signing_key,
            )
            claim = TagClaim(seeker.player_id, candidate.player_id, qr_token=token)
        else:
            claim = TagClaim(
                seeker.player_id,
                candidate.player_id,
                seeker_range=0.5,
                hider_range=0.5,
            )
        try:
            session.claim_tag(claim)
            demo.last_bot_tag_s = now_s
        except GameRuleError:
            demo.bot_backoff_until_s[seeker.player_id] = now_s + 6
            demo.bot_headings[seeker.player_id] = (
                demo.bot_headings.get(seeker.player_id, 0.0) + math.pi
            ) % _TWO_PI


def _nearest_player(
    session: GameSession,
    *,
    origin: GeoPoint,
    role: str,
    max_dist_m: float | None = None,
    active_only: bool = True,
) -> PlayerState | None:
    best: PlayerState | None = None
    best_dist = math.inf
    for player in session.state.players.values():
        if player.role != role:
            continue
        if active_only and player.status != "active":
            continue
        if player.location is None:
            continue
        dist = distance_m(origin, player.location.point)
        if max_dist_m is not None and dist > max_dist_m:
            continue
        if dist < best_dist:
            best_dist = dist
            best = player
    return best


def _pick_chase_hider(session: GameSession, origin: GeoPoint) -> PlayerState | None:
    now_s = session.state.game_elapsed_s
    best: PlayerState | None = None
    best_dist = math.inf
    for player in session.state.players.values():
        if player.role != "hider" or player.status != "active" or player.location is None:
            continue
        if player.safe_zone_id is not None and not player.safe_expired:
            continue
        dist = distance_m(origin, player.location.point)
        taunting = player.taunt_until_s is not None and player.taunt_until_s > now_s
        if dist <= _CHASE_VISION_M or taunting:
            if dist < best_dist:
                best_dist = dist
                best = player
    return best


def _nearest_reveal_point(session: GameSession, origin: GeoPoint) -> GeoPoint | None:
    best: GeoPoint | None = None
    best_dist = math.inf
    for pin in session.state.reveals:
        pt = GeoPoint(lat=pin.lat, lon=pin.lon)
        dist = distance_m(origin, pt)
        if dist < best_dist:
            best_dist = dist
            best = pt
    return best
