"""Mutable in-memory session state. Timers use game_elapsed_s except signal-loss."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from uuid import UUID

from app.engine.arena import Arena
from app.engine.geo import GeoPoint


@dataclass
class LocationReading:
    lat: float
    lon: float
    accuracy_m: float
    recorded_at: datetime
    battery: float | None = None
    flag: str = "normal"

    @property
    def point(self) -> GeoPoint:
        return GeoPoint(lat=self.lat, lon=self.lon)


@dataclass
class RevealPin:
    reveal_id: UUID
    player_id: UUID
    lat: float
    lon: float
    radius_m: float
    expires_at_game_s: int


@dataclass
class Banner:
    banner_id: UUID
    tone: str
    title: str
    detail: str
    player_id: UUID | None = None


@dataclass
class Effect:
    effect_id: UUID
    owner_id: UUID
    target_id: UUID | None
    type: str
    expires_at_game_s: int | None
    payload: dict[str, Any] = field(default_factory=dict)


@dataclass
class PlayerState:
    player_id: UUID
    display_name: str
    is_host: bool
    role: str = "unassigned"
    status: str = "active"
    points: int = 100
    location: LocationReading | None = None
    last_precise: LocationReading | None = None
    bounds_phase: str = "inside"
    bounds_remaining_s: int | None = None
    oob_revealed: bool = False
    safe_zone_id: UUID | None = None
    safe_remaining_s: int | None = None
    safe_expired: bool = False
    safe_cooldown_until_s: int | None = None
    last_location_at: datetime | None = None
    ghost_next_reveal: bool = False
    decoy_point: GeoPoint | None = None
    shield_until_s: int | None = None
    radar_until_s: int | None = None
    jammer_until_s: int | None = None
    tracker_until_s: int | None = None
    lockdown_until_s: int | None = None
    taunt_until_s: int | None = None
    cooldowns: dict[str, int] = field(default_factory=dict)
    close_near_since_s: int | None = None
    last_survival_award_s: int = 0
    hint: dict[str, Any] | None = None
    # Game second when the current hint was published. None means "recompute".
    hint_at_s: int | None = None
    uwb_token: str | None = None
    # This phone's own range to a peer: meters, game_elapsed_s. Not persisted.
    uwb_ranges: dict[UUID, tuple[float, int]] = field(default_factory=dict)
    battery: float | None = None


@dataclass
class WinResult:
    winner: str
    reason: str
    ended_at: datetime | None = None


@dataclass
class GameState:
    game_id: UUID
    join_code: str
    arena: Arena
    preset: dict[str, Any]
    seed: int
    phase: str = "lobby"
    paused_from: str | None = None
    game_elapsed_s: int = 0
    phase_remaining_s: int | None = None
    # Sample lobby countdown. The realtime loop writes it; the engine does not.
    lobby_starts_in_s: int | None = None
    time_limit_remaining_s: int | None = None
    players: dict[UUID, PlayerState] = field(default_factory=dict)
    reveals: list[RevealPin] = field(default_factory=list)
    banners: list[Banner] = field(default_factory=list)
    result: WinResult | None = None
    next_seq: int = 1
    last_reveal_at_s: int | None = None
    qr_by_hider: dict[UUID, tuple[str, datetime]] = field(default_factory=dict)
    effects: list[Effect] = field(default_factory=list)
    event_log: list = field(default_factory=list)
    last_tag: dict[str, Any] | None = None
    safety_needs_ack: bool = False
    lockdown_until_s: int | None = None
    jammer_until_s: int | None = None
    inputs: list[dict[str, Any]] = field(default_factory=list)
    # Last uwb_peers payload sent to each socket. In memory only, so a restart
    # makes phones publish discovery tokens again.
    uwb_peer_signature: dict[UUID, tuple[str, ...]] = field(default_factory=dict)
