from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.arena import CircleShape, PolygonShape, ZoneKind
from app.engine.geo import (
    ACCURACY_CUTOFF_M,
    GeoPoint,
    circle_covers,
    contains,
    is_confidently_outside,
)
from app.engine.modules.base import BaseModule, TagClaim
from app.engine.state import Banner
from app.errors import ErrorCode

if TYPE_CHECKING:
    from app.engine.session import GameSession
    from app.engine.state import PlayerState


class ZonePolicyModule(BaseModule):
    module_id: ClassVar[str] = "zone_policy"

    def on_tick(self, s: GameSession) -> None:
        if not bool(self.settings.get("enabled", True)):
            return
        margin = float(self.settings.get("margin_m", 5))
        countdown = int(self.settings.get("oob_countdown", 15))
        safe_visit = int(self.settings.get("safe_visit", 60))
        play = s.state.arena.boundary
        for player in s.state.players.values():
            reading = player.location
            if reading is None or reading.accuracy_m > ACCURACY_CUTOFF_M:
                continue
            point = reading.point
            outside = is_confidently_outside(point, reading.accuracy_m, play, margin)
            if not outside:
                for zone in s.state.arena.zones:
                    if zone.kind == ZoneKind.OUT_OF_BOUNDS and _in_zone(point, zone):
                        outside = True
                        break
            _advance_bounds(player, outside, countdown)
            if player.role == "hider" and player.bounds_phase == "penalized":
                if player.status == "active":
                    player.status = "eliminated"
                    s.emit(
                        "out_of_bounds",
                        {"text": f"{player.display_name} was tagged out of bounds."},
                        player_id=player.player_id,
                        tone="warning",
                    )
            player.oob_revealed = player.role == "seeker" and player.bounds_phase != "inside"
            _advance_safe(s, player, point, safe_visit)

    def check_tag(self, s: GameSession, claim: TagClaim) -> ErrorCode | None:
        hider = s.state.players.get(claim.hider_id)
        if hider is None:
            return ErrorCode.TARGET_NOT_ACTIVE
        if s.state.lockdown_until_s is not None:
            return None
        if hider.safe_zone_id is not None and not hider.safe_expired:
            return ErrorCode.TARGET_IN_SAFE_ZONE
        return None


def _in_zone(point: GeoPoint, zone) -> bool:
    if isinstance(zone.shape, CircleShape):
        return circle_covers(zone.shape.center, zone.shape.radius_m, point)
    if isinstance(zone.shape, PolygonShape):
        return contains(point, zone.shape.vertices)
    return False


def _advance_bounds(player: PlayerState, is_outside: bool, countdown: int) -> None:
    if not is_outside:
        player.bounds_phase = "inside"
        player.bounds_remaining_s = None
        return
    if player.bounds_phase == "inside":
        player.bounds_phase = "warning"
        player.bounds_remaining_s = None
    elif player.bounds_phase == "warning":
        player.bounds_phase = "countdown"
        player.bounds_remaining_s = countdown
    elif player.bounds_phase == "countdown":
        remaining = (player.bounds_remaining_s or 1) - 1
        if remaining <= 0:
            player.bounds_phase = "penalized"
            player.bounds_remaining_s = None
        else:
            player.bounds_remaining_s = remaining
    # penalized stays until they come back inside


def _advance_safe(s: GameSession, player: PlayerState, point: GeoPoint, visit: int) -> None:
    inside_id = None
    for zone in s.state.arena.zones:
        if zone.kind == ZoneKind.SAFE and _in_zone(point, zone):
            inside_id = zone.id
            break
    if inside_id is None:
        if player.safe_zone_id is not None:
            cooldown = int(s.module_settings("zone_policy").get("safe_cooldown", 60))
            player.safe_cooldown_until_s = s.state.game_elapsed_s + cooldown
        player.safe_zone_id = None
        player.safe_remaining_s = None
        player.safe_expired = False
        return
    cooling = player.safe_cooldown_until_s
    if cooling is not None and s.state.game_elapsed_s < cooling:
        return
    if player.safe_zone_id != inside_id:
        player.safe_zone_id = inside_id
        player.safe_remaining_s = visit
        player.safe_expired = False
        s.state.banners = [
            b
            for b in s.state.banners
            if not (b.player_id == player.player_id and b.title.startswith("Safe"))
        ]
        return
    if player.safe_expired:
        return
    remaining = (player.safe_remaining_s or 1) - 1
    player.safe_remaining_s = max(0, remaining)
    if remaining <= 0:
        player.safe_expired = True
        s.state.banners.append(
            Banner(
                banner_id=uuid4(),
                tone="warning",
                title="Safe time is up",
                detail="You can be tagged until you leave and the cooldown passes.",
                player_id=player.player_id,
            )
        )
