"""In-memory GameSession. Time comes from Clock; randomness from Random(seed)."""

from __future__ import annotations

import random
from typing import Any
from uuid import UUID

from app.engine.arena import Arena
from app.engine.clock import Clock
from app.engine.events import GameEvent
from app.engine.modules import MODULE_TYPES, BaseModule
from app.engine.modules.base import TagClaim
from app.engine.modules.tag_policy import TagPolicyModule, require_tag_ok
from app.engine.state import GameState, LocationReading, PlayerState, WinResult
from app.errors import ErrorCode, GameRuleError


class GameSession:
    def __init__(
        self,
        game_id: UUID,
        arena: Arena,
        preset: dict[str, Any],
        clock: Clock,
        seed: int,
        *,
        join_code: str = "PARK42",
        qr_signing_key: str = "dev-qr-signing-key-change-me",
    ) -> None:
        self.clock = clock
        self.rng = random.Random(seed)
        self.qr_signing_key = qr_signing_key
        self.modules: list[BaseModule] = []
        for module_id, settings in preset.get("modules", {}).items():
            cls = MODULE_TYPES.get(module_id)
            if cls is None:
                continue
            self.modules.append(cls(settings))
        self.state = GameState(
            game_id=game_id,
            join_code=join_code,
            arena=arena,
            preset=preset,
            seed=seed,
        )
        self._pending: list[GameEvent] = []

    def module_settings(self, module_id: str) -> dict[str, Any]:
        return self.state.preset.get("modules", {}).get(module_id, {})

    def add_player(self, player_id: UUID, display_name: str, is_host: bool) -> PlayerState:
        if len(self.state.players) >= 20:
            raise GameRuleError(ErrorCode.GAME_FULL)
        if self.state.phase != "lobby":
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        player = PlayerState(
            player_id=player_id,
            display_name=display_name,
            is_host=is_host,
        )
        self.state.players[player_id] = player
        self.emit("player_joined", {"text": f"{display_name} joined."}, player_id=player_id)
        return player

    def assign_roles_random(self, hider_count: int) -> None:
        ids = list(self.state.players.keys())
        if not ids:
            return
        shuffled = ids[:]
        self.rng.shuffle(shuffled)
        hiders = max(0, min(hider_count, len(shuffled)))
        for index, player_id in enumerate(shuffled):
            self.state.players[player_id].role = "hider" if index < hiders else "seeker"

    def set_role(self, player_id: UUID, role: str) -> None:
        player = self.state.players[player_id]
        player.role = role

    def start(self) -> None:
        if self.state.phase != "lobby":
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        roles = {p.role for p in self.state.players.values()}
        if "hider" not in roles or "seeker" not in roles:
            raise GameRuleError(ErrorCode.NEED_BOTH_ROLES)
        for module in self.modules:
            module.on_start(self)
        self.emit("started", {"text": "The hunt is on."})

    def pause(self) -> None:
        if self.state.phase not in {"head_start", "active"}:
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        self.state.paused_from = self.state.phase
        self.state.phase = "paused"
        self.emit("paused", {"text": "The host stopped the clock."})

    def resume(self) -> None:
        if self.state.phase != "paused":
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        self.state.phase = self.state.paused_from or "active"
        self.state.paused_from = None
        self.emit("resumed", {"text": "The hunt is back on."})

    def end(self, reason: str, winner: str = "none") -> None:
        self.state.phase = "ended"
        self.state.result = WinResult(winner=winner, reason=reason, ended_at=self.clock.now())
        self.emit("ended", {"text": reason, "winner": winner})

    def record_location(self, player_id: UUID, reading: LocationReading) -> None:
        player = self.state.players[player_id]
        player.location = reading
        player.last_location_at = reading.recorded_at
        if reading.accuracy_m <= 30:
            player.last_precise = reading
        for module in self.modules:
            module.on_location(self, player, reading)

    def claim_tag(self, claim: TagClaim) -> None:
        require_tag_ok(self, claim)
        for module in self.modules:
            if isinstance(module, TagPolicyModule):
                module.apply_tag(self, claim)
                break
        self._check_win()

    def tick(self) -> None:
        if self.state.phase not in {"head_start", "active"}:
            for module in self.modules:
                if self.state.phase == "paused":
                    # Safety (signal loss) still runs on pause; other timers do not.
                    if module.module_id == "signal_loss":
                        module.on_tick(self)
            return
        self.state.game_elapsed_s += 1
        for module in self.modules:
            module.on_tick(self)
        self._check_win()

    def emit(
        self,
        type: str,
        payload: dict[str, Any],
        *,
        player_id: UUID | None = None,
        tone: str = "info",
        sensitive: bool = False,
    ) -> GameEvent:
        event = GameEvent(
            seq=self.state.next_seq,
            type=type,
            payload=payload,
            tone=tone,
            player_id=player_id,
            sensitive=sensitive,
            created_at=self.clock.now(),
            text=str(payload.get("text", "")),
        )
        self.state.next_seq += 1
        self._pending.append(event)
        for module in self.modules:
            module.on_event(self, event)
        return event

    def drain_events(self) -> list[GameEvent]:
        events = self._pending[:]
        self._pending.clear()
        return events

    def _check_win(self) -> None:
        if self.state.phase == "ended":
            return
        for module in self.modules:
            result = module.check_win(self)
            if result is not None:
                result.ended_at = self.clock.now()
                self.state.result = result
                self.state.phase = "ended"
                self.emit("ended", {"text": result.reason, "winner": result.winner})
                return
