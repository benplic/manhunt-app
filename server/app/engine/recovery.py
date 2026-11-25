"""Rebuild a GameSession from the deterministic seed plus logged inputs."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any
from uuid import UUID

from app.engine.arena import Arena
from app.engine.clock import FakeClock
from app.engine.modules.base import TagClaim
from app.engine.session import GameSession
from app.engine.state import LocationReading
from app.errors import ErrorCode, GameRuleError
from app.playtest_log import get_playtest_log

log = logging.getLogger("manhunt.recovery")

# Rule errors that mean "this input already took effect". Replay can reach that state
# when a tick during replay lands the same elimination or phase change a logged input
# also records (for example PS95VZ: a tag on a hider who was already out, which aborted
# the whole rebuild with TARGET_NOT_ACTIVE). Each rejected call fails before it mutates
# anything, so skipping it leaves the session exactly as it already is.
#
# Anything not listed here still aborts the rebuild. That is deliberate: an unexpected
# error means the log and the engine disagree in a way we should not paper over.
# Live request paths never use this table and still raise.
_ALREADY_APPLIED: dict[str, frozenset[ErrorCode]] = {
    "tag": frozenset({ErrorCode.TARGET_NOT_ACTIVE, ErrorCode.WRONG_PHASE}),
    "start": frozenset({ErrorCode.WRONG_PHASE}),
    "pause": frozenset({ErrorCode.WRONG_PHASE}),
    "resume": frozenset({ErrorCode.WRONG_PHASE}),
}


def rebuild_session(
    *,
    game_id: UUID,
    arena: Arena,
    preset: dict[str, Any],
    seed: int,
    join_code: str,
    inputs: list[dict[str, Any]],
    qr_key: str,
) -> GameSession:
    start = datetime.fromisoformat(inputs[0]["at"]) if inputs else None
    clock = FakeClock(start)
    session = GameSession(
        game_id=game_id,
        arena=arena,
        preset=preset,
        clock=clock,
        seed=seed,
        join_code=join_code,
        qr_signing_key=qr_key,
    )
    session.replaying = True
    last_elapsed = 0
    for item in inputs:
        at = datetime.fromisoformat(item["at"])
        clock.set(at)
        elapsed = int(item.get("game_elapsed_s") or 0)
        while session.state.game_elapsed_s < elapsed and session.state.phase in {
            "head_start",
            "active",
        }:
            session.tick()
            last_elapsed = session.state.game_elapsed_s
        try:
            _apply(session, item)
        except GameRuleError as exc:
            if not _already_applied(session, item, exc.code):
                raise
            log.warning(
                "replay_input_skipped game_id=%s kind=%s code=%s game_elapsed_s=%s",
                game_id,
                item.get("kind"),
                exc.code.value,
                session.state.game_elapsed_s,
            )
            get_playtest_log().emit(
                "replay_input_skipped",
                game_id=game_id,
                join_code=join_code,
                kind=item.get("kind"),
                code=exc.code.value,
                game_elapsed_s=session.state.game_elapsed_s,
            )
        last_elapsed = elapsed
    session.replaying = False
    # Replay does not re-log inputs. Without this the next persist would seal an empty
    # list over the stored history and the following restart could not rebuild at all.
    session.state.inputs = list(inputs)
    # TODO: replay only ticks up to the last logged input, so shrink steps without
    # a subsequent input rely on the next live tick to catch up.
    _ = last_elapsed
    return session


def _already_applied(session: GameSession, item: dict[str, Any], code: ErrorCode) -> bool:
    """True only when the session state proves the rejected input already took effect.

    A rule error alone is not proof: it could also mean the log and the engine disagree.
    So each tolerated kind must also match the state it claims to have already reached.
    Anything else aborts the rebuild so a real divergence stays visible.
    """
    kind = str(item.get("kind"))
    if code not in _ALREADY_APPLIED.get(kind, frozenset()):
        return False
    state = session.state
    if kind == "tag":
        if code == ErrorCode.WRONG_PHASE:
            return state.phase == "ended"
        hider = state.players.get(UUID(str((item.get("payload") or {}).get("hider_id"))))
        # The target is already out (or converted): this tag's effect is in the state.
        return hider is not None and (hider.status != "active" or hider.role != "hider")
    if kind == "start":
        return state.phase != "lobby"
    if kind == "pause":
        return state.phase in {"paused", "ended"}
    if kind == "resume":
        return state.phase in {"head_start", "active", "ended"}
    return False


def _apply(session: GameSession, item: dict[str, Any]) -> None:
    kind = item["kind"]
    payload = dict(item.get("payload") or {})
    if kind == "player_joined":
        session.add_player(
            UUID(str(payload["player_id"])),
            str(payload["display_name"]),
            bool(payload["is_host"]),
        )
    elif kind == "roles_random":
        if "seeker_count" in payload:
            session.assign_roles_random(int(payload["seeker_count"]))
        else:
            session.assign_hiders_random(int(payload.get("hider_count", 1)))
    elif kind == "role_set":
        session.set_role(UUID(str(payload["player_id"])), str(payload["role"]))
    elif kind == "start":
        session.start()
    elif kind == "pause":
        session.pause()
    elif kind == "resume":
        session.resume()
    elif kind == "end":
        session.end(str(payload.get("reason", "")), winner=str(payload.get("winner", "none")))
    elif kind == "location":
        session.record_location(
            UUID(str(payload["player_id"])),
            LocationReading(
                lat=float(payload["lat"]),
                lon=float(payload["lon"]),
                accuracy_m=float(payload["accuracy_m"]),
                recorded_at=session.clock.now(),
                battery=payload.get("battery"),
                flag=str(payload.get("flag", "normal")),
            ),
        )
    elif kind == "tag":
        session.claim_tag(
            TagClaim(
                UUID(str(payload["seeker_id"])),
                UUID(str(payload["hider_id"])),
                seeker_range=payload.get("seeker_range"),
                hider_range=payload.get("hider_range"),
                qr_token=payload.get("qr_token"),
            )
        )
    elif kind == "purchase":
        player_id = UUID(str(payload.pop("player_id")))
        power_id = str(payload.pop("power_id"))
        session.purchase(player_id, power_id, **payload)
    elif kind == "taunt":
        session.taunt(UUID(str(payload["player_id"])))
    elif kind == "player_removed":
        session.remove_player(UUID(str(payload["player_id"])))
    elif kind == "tag_undone":
        session.undo_tag()
    elif kind == "idle_wake":
        session.wake_from_idle()
