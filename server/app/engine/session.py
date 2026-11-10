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
from app.engine.uwb import UWB_RANGE_FRESH_S, UWB_RANGE_MAX_M, select_uwb_peers, token_ok
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
        self.replaying = False

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

    def assign_roles_random(self, hider_count: int) -> None:
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

    def set_uwb_token(self, player_id: UUID, token: str) -> None:
        """Store a discovery token. Not logged and not written to the input log."""
        if player_id not in self.state.players or not token_ok(token):
            raise GameRuleError(ErrorCode.VALIDATION_FAILED, "Discovery token length is invalid.")
        self.state.players[player_id].uwb_token = token

    def report_uwb_range(self, player_id: UUID, peer_id: UUID, distance_m: float) -> bool:
        """Store this phone's own range. Drop it when the peer is not selected.

        The range is not logged. A seeker cannot report the hider's measurement.
        """
        player = self.state.players.get(player_id)
        if player is None or distance_m < 0 or distance_m > UWB_RANGE_MAX_M:
            return False
        self.prune_uwb_ranges()
        allowed = _peer_ids(select_uwb_peers(self.state.players.values()).get(player_id, []))
        if peer_id not in allowed:
            player.uwb_ranges.pop(peer_id, None)
            return False
        player.uwb_ranges[peer_id] = (float(distance_m), self.state.game_elapsed_s)
        return True

    def prune_uwb_ranges(self) -> None:
        """Drop stored ranges for peers who no longer pass the GPS gate."""
        selected = select_uwb_peers(self.state.players.values())
        for player_id, player in self.state.players.items():
            allowed = _peer_ids(selected.get(player_id, []))
            player.uwb_ranges = {
                peer_id: sample
                for peer_id, sample in player.uwb_ranges.items()
                if peer_id in allowed
            }

    def claim_uwb(self, seeker_id: UUID, hider_id: UUID) -> None:
        """Tag from the two stored ranges. The seeker does not supply the hider's.

        Live range reports stay out of the input log. claim_tag records the two
        distances that were accepted so a restart can replay the tag.
        """
        self.prune_uwb_ranges()
        seeker = self.state.players.get(seeker_id)
        hider = self.state.players.get(hider_id)
        if seeker is None or hider is None:
            raise GameRuleError(ErrorCode.TARGET_NOT_ACTIVE)
        now = self.state.game_elapsed_s
        self.claim_tag(
            TagClaim(
                seeker_id,
                hider_id,
                seeker_range=_fresh_range(seeker.uwb_ranges.get(hider_id), now),
                hider_range=_fresh_range(hider.uwb_ranges.get(seeker_id), now),
            )
        )

    def claim_tag(self, claim: TagClaim) -> None:
        require_tag_ok(self, claim)
        hider = self.state.players[claim.hider_id]
        seeker = self.state.players[claim.seeker_id]
        self.state.last_tag = {
            "hider_id": str(hider.player_id),
            "seeker_id": str(seeker.player_id),
            "hider_status": hider.status,
            "hider_role": hider.role,
            "seeker_points": seeker.points,
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


def _peer_ids(peers: list[dict[str, str]]) -> set[UUID]:
    return {UUID(peer["player_id"]) for peer in peers}


def _fresh_range(sample: tuple[float, int] | None, now_s: int) -> float | None:
    if sample is None:
        return None
    meters, at_s = sample
    if now_s - at_s > UWB_RANGE_FRESH_S:
        return None
    return meters
