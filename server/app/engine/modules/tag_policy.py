from __future__ import annotations

import math
from typing import TYPE_CHECKING, ClassVar

from app.engine.geo import ACCURACY_CUTOFF_M, distance_m
from app.engine.modules.base import BaseModule, TagClaim
from app.engine.modules.points import grant_points
from app.engine.qr import parse_qr_token
from app.errors import ErrorCode, GameRuleError

if TYPE_CHECKING:
    from app.engine.session import GameSession


class TagPolicyModule(BaseModule):
    module_id: ClassVar[str] = "tag_policy"

    def check_tag(self, s: GameSession, claim: TagClaim) -> ErrorCode | None:
        seeker = s.state.players.get(claim.seeker_id)
        hider = s.state.players.get(claim.hider_id)
        if seeker is None or hider is None:
            return ErrorCode.TARGET_NOT_ACTIVE
        if seeker.role != "seeker":
            return ErrorCode.WRONG_ROLE
        if hider.role != "hider" or hider.status != "active":
            return ErrorCode.TARGET_NOT_ACTIVE
        if s.state.phase not in {"active"}:
            return ErrorCode.WRONG_PHASE
        if claim.qr_token:
            hid = parse_qr_token(
                claim.qr_token,
                game_id=s.state.game_id,
                key=s.qr_signing_key,
                now=s.clock.now(),
            )
            if hid != claim.hider_id:
                return ErrorCode.TOKEN_INVALID
        pairing = float(self.settings.get("pairing_m", 30))
        radius = float(self.settings.get("radius_m", 2))
        sloc = seeker.location
        hloc = hider.location
        if sloc is None or hloc is None:
            return ErrorCode.NOT_IN_PAIRING_RANGE
        if sloc.accuracy_m > ACCURACY_CUTOFF_M or hloc.accuracy_m > ACCURACY_CUTOFF_M:
            return ErrorCode.NOT_IN_PAIRING_RANGE
        gps = distance_m(sloc.point, hloc.point)
        if gps > pairing + sloc.accuracy_m + hloc.accuracy_m:
            return ErrorCode.NOT_IN_PAIRING_RANGE
        # Spec §5.6: a signed QR claim is the fallback when UWB is unavailable
        # or ranging fails. GPS pairing above still applies; dual-range is only
        # required for UWB claims (no qr_token).
        if claim.qr_token:
            return None
        method = str(self.settings.get("method", "qr"))
        if method == "uwb":
            if claim.seeker_range is None or claim.hider_range is None:
                return ErrorCode.NOT_IN_RANGE
            if not _finite_within(claim.seeker_range, radius) or not _finite_within(
                claim.hider_range, radius
            ):
                return ErrorCode.NOT_IN_RANGE
        elif claim.seeker_range is not None and claim.hider_range is not None:
            # Reject a far GPS pair "saved" by a forged close reading when both
            # ranges are supplied on a QR-method game.
            if not _finite_within(claim.seeker_range, radius) or not _finite_within(
                claim.hider_range, radius
            ):
                return ErrorCode.NOT_IN_RANGE
        return None

    def apply_tag(self, s: GameSession, claim: TagClaim) -> None:
        result = self.settings.get("result", "eliminate")
        hider = s.state.players[claim.hider_id]
        seeker = s.state.players[claim.seeker_id]
        if result == "convert":
            hider.role = "seeker"
            hider.status = "active"
        else:
            hider.status = "eliminated"
        grant_points(seeker, 25)
        s.emit(
            "tag",
            {"text": f"{seeker.display_name} tagged {hider.display_name}."},
            player_id=hider.player_id,
            tone="success",
        )


def require_tag_ok(s: GameSession, claim: TagClaim) -> None:
    for module in s.modules:
        code = module.check_tag(s, claim)
        if code is not None:
            raise GameRuleError(code)


def _finite_within(distance_m: float, radius: float) -> bool:
    return math.isfinite(distance_m) and 0 <= distance_m <= radius
