from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.geo import ACCURACY_CUTOFF_M, distance_m
from app.engine.modules.base import BaseModule, TagClaim
from app.engine.modules.points import grant_points
from app.engine.qr import parse_qr_token
from app.errors import ErrorCode, GameRuleError

if TYPE_CHECKING:
    from app.engine.session import GameSession

# The phone reports its own accuracy. Adding the whole number lets a seeker
# claim 30 m of error and tag from the far side of a reveal circle.
ACCURACY_BONUS_CAP_M = 5.0
# Host UI no longer exposes pairing; keep GPS pairing fixed.
PAIRING_M = 30.0


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
        pairing = PAIRING_M
        sloc = seeker.location
        hloc = hider.location
        # Same error code for clients; distinct messages so web GPS noise is not "too far".
        if sloc is None or hloc is None:
            raise GameRuleError(
                ErrorCode.NOT_IN_PAIRING_RANGE,
                "Need a fresh location from both phones before tagging.",
            )
        if sloc.accuracy_m > ACCURACY_CUTOFF_M or hloc.accuracy_m > ACCURACY_CUTOFF_M:
            raise GameRuleError(
                ErrorCode.NOT_IN_PAIRING_RANGE,
                "GPS is too fuzzy to tag. Wait for a clearer fix.",
            )
        gps = distance_m(sloc.point, hloc.point)
        bonus = min(sloc.accuracy_m, ACCURACY_BONUS_CAP_M) + min(
            hloc.accuracy_m, ACCURACY_BONUS_CAP_M
        )
        if gps > pairing + bonus:
            raise GameRuleError(
                ErrorCode.NOT_IN_PAIRING_RANGE,
                "Get closer. GPS says you are too far to tag.",
            )
        if not claim.qr_token:
            return ErrorCode.TOKEN_INVALID
        hid = parse_qr_token(
            claim.qr_token,
            game_id=s.state.game_id,
            key=s.qr_signing_key,
            now=s.clock.now(),
        )
        if hid != claim.hider_id:
            return ErrorCode.TOKEN_INVALID
        return None

    def apply_tag(self, s: GameSession, claim: TagClaim) -> None:
        result = self.settings.get("result", "eliminate")
        hider = s.state.players[claim.hider_id]
        seeker = s.state.players[claim.seeker_id]
        if result == "convert":
            hider.role = "seeker"
            hider.status = "active"
            hider.converted_from_hider = True
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