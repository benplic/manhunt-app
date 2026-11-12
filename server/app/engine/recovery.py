"""Rebuild a GameSession from the deterministic seed plus logged inputs."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from app.engine.arena import Arena
from app.engine.clock import FakeClock
from app.engine.modules.base import TagClaim
from app.engine.session import GameSession
from app.engine.state import LocationReading


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
        _apply(session, item)
        last_elapsed = elapsed
    session.replaying = False
    # TODO: replay only ticks up to the last logged input, so shrink steps without
    # a subsequent input rely on the next live tick to catch up.
    _ = last_elapsed
    return session


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
        session.assign_roles_random(int(payload.get("hider_count", 1)))
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
