from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

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
        # The scanned code is the proximity check. GPS distance used to reject
        # a real tag when the web pin was stuck on a desk seed.
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
            {
                "text": f"{seeker.display_name} tagged {hider.display_name}.",
                "announcement": "player_tagged",
                "subject_name": hider.display_name,
            },
            player_id=hider.player_id,
            tone="success",
        )


def require_tag_ok(s: GameSession, claim: TagClaim) -> None:
    for module in s.modules:
        code = module.check_tag(s, claim)
        if code is not None:
            raise GameRuleError(code)