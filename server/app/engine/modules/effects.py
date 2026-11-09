"""Timed effects owned by a player. Expiry is in game seconds."""

from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar
from uuid import uuid4

from app.engine.modules.base import BaseModule
from app.engine.state import Effect

if TYPE_CHECKING:
    from app.engine.session import GameSession


class EffectsModule(BaseModule):
    module_id: ClassVar[str] = "effects"

    def on_tick(self, s: GameSession) -> None:
        live: list[Effect] = []
        now = s.state.game_elapsed_s
        for effect in s.state.effects:
            if effect.expires_at_game_s is not None and effect.expires_at_game_s <= now:
                _clear(s, effect)
                continue
            live.append(effect)
        s.state.effects = live
        lockdown = any(e.type == "lockdown" for e in live)
        jammer = any(e.type == "jammer" for e in live)
        s.state.lockdown_until_s = now + 1 if lockdown else None
        s.state.jammer_until_s = now + 1 if jammer else None


def add_effect(
    s: GameSession,
    *,
    owner_id,
    type: str,
    duration_s: int | None,
    target_id=None,
    payload: dict | None = None,
) -> Effect:
    expires = None if duration_s is None else s.state.game_elapsed_s + duration_s
    effect = Effect(
        effect_id=uuid4(),
        owner_id=owner_id,
        target_id=target_id,
        type=type,
        expires_at_game_s=expires,
        payload=payload or {},
    )
    s.state.effects.append(effect)
    return effect


def has_effect(s: GameSession, type: str, owner_id=None) -> bool:
    for effect in s.state.effects:
        if effect.type != type:
            continue
        if owner_id is not None and effect.owner_id != owner_id:
            continue
        return True
    return False


def _clear(s: GameSession, effect: Effect) -> None:
    player = s.state.players.get(effect.owner_id)
    if player is None:
        return
    if effect.type == "shield":
        player.shield_until_s = None
    elif effect.type == "radar":
        player.radar_until_s = None
    elif effect.type == "tracker":
        player.tracker_until_s = None
    elif effect.type == "taunt":
        player.taunt_until_s = None
