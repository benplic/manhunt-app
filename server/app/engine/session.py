"""In-memory GameSession. Time comes from Clock; randomness from Random(seed)."""

from __future__ import annotations

import random
from datetime import datetime
from typing import Any
from uuid import UUID

from app.engine.arena import Arena
from app.engine.clock import Clock
from app.engine.events import GameEvent
from app.engine.geo import distance_m
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
            initial_radius_m=arena.boundary_circle.radius_m if arena.boundary_circle else None,
        )
        self._pending: list[GameEvent] = []
        self.replaying = False
        # Highest seq known committed to game_events. Persist skips seq <= this.
        self.last_persisted_seq: int = 0
        # Sample lobby (PARK42). The realtime loop counts this down. Not engine time.
        self.sample_start_after_s: int | None = None
        self.sample_waited_s = 0
        self.demo: Any = None

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
        self._note_input(
            "player_joined",
            {"player_id": str(player_id), "display_name": display_name, "is_host": is_host},
        )
        return player

    def assign_roles_random(self, seeker_count: int) -> None:
        ids = list(self.state.players.keys())
        if not ids:
            return
        shuffled = ids[:]
        self.rng.shuffle(shuffled)
        seekers = max(0, min(seeker_count, len(shuffled)))
        for index, player_id in enumerate(shuffled):
            self.state.players[player_id].role = "seeker" if index < seekers else "hider"
        self._note_input("roles_random", {"seeker_count": seekers})

    def assign_hiders_random(self, hider_count: int) -> None:
        """Replay path for inputs logged before seeker_count existed."""
        ids = list(self.state.players.keys())
        if not ids:
            return
        shuffled = ids[:]
        self.rng.shuffle(shuffled)
        hiders = max(0, min(hider_count, len(shuffled)))
        for index, player_id in enumerate(shuffled):
            self.state.players[player_id].role = "hider" if index < hiders else "seeker"
        self._note_input("roles_random", {"hider_count": hiders})

    def set_role(self, player_id: UUID, role: str) -> None:
        if role not in {"hider", "seeker"}:
            raise GameRuleError(
                ErrorCode.VALIDATION_FAILED,
                "Role must be hider or seeker.",
            )
        player = self.state.players[player_id]
        player.role = role
        self._note_input("role_set", {"player_id": str(player_id), "role": role})

    def start(self) -> None:
        if self.state.phase != "lobby":
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        roles = {p.role for p in self.state.players.values()}
        if "hider" not in roles or "seeker" not in roles:
            raise GameRuleError(ErrorCode.NEED_BOTH_ROLES)
        for module in self.modules:
            module.on_start(self)
        self.emit("started", {"text": "The hunt is on."})
        self._note_input("start", {})

    def pause(self) -> None:
        if self.state.phase not in {"head_start", "active"}:
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        self.state.paused_from = self.state.phase
        self.state.phase = "paused"
        self.emit("paused", {"text": "The host stopped the clock."})
        self._note_input("pause", {})

    def resume(self) -> None:
        if self.state.phase != "paused":
            raise GameRuleError(ErrorCode.WRONG_PHASE)
        self.state.phase = self.state.paused_from or "active"
        self.state.paused_from = None
        self.emit("resumed", {"text": "The hunt is back on."})
        self._note_input("resume", {})

    def end(self, reason: str, winner: str = "none") -> None:
        # Host double-tap / racing tick must not emit a second ended event.
        if self.state.phase == "ended":
            return
        self.state.phase = "ended"
        self.state.result = WinResult(winner=winner, reason=reason, ended_at=self.clock.now())
        self.emit("ended", {"text": reason, "winner": winner})
        self._note_input("end", {"reason": reason, "winner": winner})

    def record_location(self, player_id: UUID, reading: LocationReading) -> None:
        player = self.state.players[player_id]
        player.location = reading
        player.last_location_at = reading.recorded_at
        player.battery = reading.battery
        if reading.accuracy_m <= 30:
            player.last_precise = reading
        self.emit(
            "location",
            {
                "lat": reading.lat,
                "lon": reading.lon,
                "accuracy_m": reading.accuracy_m,
                "flag": reading.flag,
                "battery": reading.battery,
            },
            player_id=player_id,
            sensitive=True,
        )
        self._note_input(
            "location",
            {
                "player_id": str(player_id),
                "lat": reading.lat,
                "lon": reading.lon,
                "accuracy_m": reading.accuracy_m,
                "flag": reading.flag,
                "battery": reading.battery,
            },
        )
        if reading.flag == "low_battery":
            self.emit(
                "low_battery",
                {"text": f"{player.display_name} is at 5% battery."},
                player_id=player_id,
                tone="warning",
            )
        if reading.flag == "final":
            self.emit(
                "final_ping",
                {"text": f"{player.display_name} sent a last fix."},
                player_id=player_id,
                tone="safety",
            )
        for module in self.modules:
            module.on_location(self, player, reading)

    def set_synthetic_location(self, player_id: UUID, reading: LocationReading) -> None:
        """Update a demo bot or virtual player location without event/input log bloat."""
        player = self.state.players[player_id]
        player.location = reading
        player.last_location_at = reading.recorded_at
        player.battery = reading.battery
        if reading.accuracy_m <= 30:
            player.last_precise = reading
        for module in self.modules:
            module.on_location(self, player, reading)

    def claim_tag(self, claim: TagClaim) -> None:
        require_tag_ok(self, claim)
        hider = self.state.players[claim.hider_id]
        seeker = self.state.players[claim.seeker_id]
        other_hiders: dict[str, dict[str, int]] = {}
        for player_id, player in self.state.players.items():
            if (
                player_id != claim.hider_id
                and player.role == "hider"
                and player.status == "active"
            ):
                other_hiders[str(player_id)] = {
                    "points": player.points,
                    "points_earned": player.points_earned,
                }
        self.state.last_tag = {
            "hider_id": str(hider.player_id),
            "seeker_id": str(seeker.player_id),
            "hider_status": hider.status,
            "hider_role": hider.role,
            "seeker_points": seeker.points,
            "seeker_points_earned": seeker.points_earned,
            "other_hiders": other_hiders,
        }
        for module in self.modules:
            if isinstance(module, TagPolicyModule):
                module.apply_tag(self, claim)
                break
        self._note_input(
            "tag",
            {
                "hider_id": str(claim.hider_id),
                "seeker_id": str(claim.seeker_id),
                "qr_token": claim.qr_token,
                "seeker_range": claim.seeker_range,
                "hider_range": claim.hider_range,
            },
        )
        self._check_win()

    def leave_player(self, player_id: UUID) -> None:
        """A player dropping out. Replay uses the same input shape as a host remove."""
        player = self.state.players.pop(player_id, None)
        if player is None:
            raise GameRuleError(ErrorCode.NOT_A_MEMBER)
        self.emit(
            "player_left",
            {"text": f"{player.display_name} left."},
            player_id=player_id,
        )
        self._note_input("player_removed", {"player_id": str(player_id)})
        self._check_win()

    def remove_player(self, player_id: UUID) -> None:
        player = self.state.players.pop(player_id, None)
        if player is None:
            raise GameRuleError(ErrorCode.NOT_A_MEMBER)
        self.emit(
            "player_removed",
            {"text": f"{player.display_name} was removed."},
            player_id=player_id,
        )
        self._note_input("player_removed", {"player_id": str(player_id)})
        self._check_win()

    def undo_tag(self) -> None:
        last = self.state.last_tag
        if not last:
            raise GameRuleError(ErrorCode.WRONG_PHASE, "No tag to undo.")
        hider = self.state.players.get(UUID(str(last["hider_id"])))
        seeker = self.state.players.get(UUID(str(last["seeker_id"])))
        if hider is None or seeker is None:
            raise GameRuleError(ErrorCode.TARGET_NOT_ACTIVE)
        hider.status = str(last["hider_status"])
        hider.role = str(last["hider_role"])
        seeker.points = int(last["seeker_points"])
        seeker.points_earned = int(
            last.get("seeker_points_earned", last["seeker_points"])
        )
        for player_id_str, snap in last.get("other_hiders", {}).items():
            other = self.state.players.get(UUID(str(player_id_str)))
            if other is None:
                continue
            other.points = int(snap["points"])
            other.points_earned = int(
                snap.get("points_earned", snap["points"])
            )
        self.state.last_tag = None
        if self.state.phase == "ended":
            self.state.phase = "active"
            self.state.result = None
        self.emit("tag_undone", {"text": "The host undid the last tag."}, tone="warning")
        self._note_input("tag_undone", {})

    def ack_safety(self, player_id: UUID) -> None:
        if not self.state.players[player_id].is_host:
            raise GameRuleError(ErrorCode.NOT_HOST)
        self.state.safety_needs_ack = False
        self.state.banners = [b for b in self.state.banners if b.tone != "safety"]
        self.emit("safety_acked", {"text": "The host acknowledged the safety alert."})

    def purchase(self, player_id: UUID, power_id: str, **kwargs: Any) -> None:
        from app.engine.modules.power_ups import apply_purchase

        apply_purchase(self, player_id, power_id, **kwargs)

    def taunt(self, player_id: UUID) -> None:
        from app.engine.modules.points import apply_taunt

        apply_taunt(self, player_id)

    def tick(self) -> None:
        if self.state.phase not in {"head_start", "active"}:
            for module in self.modules:
                if self.state.phase == "paused":
                    # Safety (signal loss) still runs on pause; other timers do not.
                    if module.module_id == "signal_loss":
                        module.on_tick(self)
            return
        from app.engine.modules.head_start import spawn_clock_held

        if spawn_clock_held(self):
            # Head start has not begun (or a seeker stepped out). The match
            # clock stays put. Spawn banners, out-of-bounds, and going-dark still run.
            for module in self.modules:
                if module.module_id in {"head_start", "zone_policy", "signal_loss"}:
                    module.on_tick(self)
            self._check_win()
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
        if self.replaying:
            return event
        self.state.next_seq += 1
        self.state.event_log.append(event)
        self._pending.append(event)
        for module in self.modules:
            module.on_event(self, event)
        return event

    def drain_events(self) -> list[GameEvent]:
        events = self._pending[:]
        self._pending.clear()
        return events

    def _note_input(self, kind: str, payload: dict[str, Any]) -> None:
        if self.replaying:
            return
        self.state.inputs.append(
            {
                "kind": kind,
                "at": self.clock.now().isoformat(),
                "game_elapsed_s": self.state.game_elapsed_s,
                "payload": payload,
            }
        )

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


def movement_too_fast(player: PlayerState, reading: LocationReading) -> bool:
    """True when a phone could not have walked from its previous fix to this one.

    8 m/s is a fast run. 40 m covers one noisy GPS hop. The engine itself may
    place a player for a demo or a test; only the socket should call this.
    """
    if player.location is None or player.last_location_at is None:
        return False
    elapsed = (reading.recorded_at - player.last_location_at).total_seconds()
    if elapsed <= 0:
        return False
    allowed_m = 8.0 * elapsed + 40.0
    return distance_m(player.location.point, reading.point) > allowed_m


def note_presence(player: PlayerState, at: datetime) -> None:
    """Refresh silence clock without moving the pin.

    Browser GPS often teleports for one sample. Rejecting that jump must not
    look like the player went dark.
    """
    player.last_location_at = at


