"""Nearby Interaction peer selection.

The server only relays discovery tokens. It does not interpret them, and it
does not write tokens or ranges to the event log.

Apple does not publish a numeric NISession cap. WWDC20 shows one session per
peer and "several" at once. NIError.Code.activeSessionsLimitExceeded is the
runtime failure, and opening too many sessions invalidates all of them.
UWB_MAX_PEERS is 5 until that is measured on device.
TODO: measure the cap on two iPhone 11 or newer running the iOS version under test.
"""

from __future__ import annotations

from collections.abc import Iterable
from uuid import UUID

from app.engine.geo import ACCURACY_CUTOFF_M, distance_m
from app.engine.state import PlayerState

# See the module docstring. Do not raise this without a device measurement.
UWB_MAX_PEERS = 5
UWB_PAIR_M = 30.0
UWB_TOKEN_MIN = 16
UWB_TOKEN_MAX = 4096
UWB_RANGE_FRESH_S = 3
# A reported UWB distance above the GPS gate cannot be a real ranging sample.
UWB_RANGE_MAX_M = 30.0


def select_uwb_peers(
    players: Iterable[PlayerState],
    *,
    cap: int = UWB_MAX_PEERS,
    max_m: float = UWB_PAIR_M,
) -> dict[UUID, list[dict[str, str]]]:
    """Closest opposite-role opponents within max_m, at most `cap` each.

    A player without a discovery token, or with accuracy worse than 30 m, is
    omitted. The result is not forced to be symmetric: each player keeps their
    own closest opponents.
    """
    usable = [player for player in players if _usable(player)]
    selected: dict[UUID, list[dict[str, str]]] = {}
    for player in usable:
        ranked: list[tuple[float, str, PlayerState]] = []
        for other in usable:
            if other.player_id == player.player_id or other.role == player.role:
                continue
            assert player.location is not None and other.location is not None
            dist = distance_m(player.location.point, other.location.point)
            if dist > max_m:
                continue
            ranked.append((dist, str(other.player_id), other))
        ranked.sort(key=lambda item: (item[0], item[1]))
        peers = [
            {
                "player_id": str(other.player_id),
                "display_name": other.display_name,
                "token": other.uwb_token or "",
            }
            for _, _, other in ranked[:cap]
        ]
        if peers:
            selected[player.player_id] = peers
    return selected


def token_ok(token: str) -> bool:
    return UWB_TOKEN_MIN <= len(token) <= UWB_TOKEN_MAX


def _usable(player: PlayerState) -> bool:
    loc = player.location
    if loc is None or loc.accuracy_m > ACCURACY_CUTOFF_M:
        return False
    if player.status != "active" or player.role not in {"hider", "seeker"}:
        return False
    return bool(player.uwb_token) and token_ok(player.uwb_token or "")
