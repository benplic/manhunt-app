"""Arena snapshots and validation. Geometry is JSON, not PostGIS."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any
from uuid import UUID, uuid4

from app.engine.geo import (
    GeoPoint,
    circle_inside_play_area,
    circle_sample_ring,
    clip_polygon,
    polygon_inside_play_area,
    self_intersects,
)


class ZoneKind(StrEnum):
    SAFE = "safe"
    OUT_OF_BOUNDS = "out_of_bounds"
    SEEKER_SPAWN = "seeker_spawn"


@dataclass
class CircleShape:
    center: GeoPoint
    radius_m: float
    type: str = "circle"


@dataclass
class PolygonShape:
    vertices: list[GeoPoint]
    type: str = "polygon"


@dataclass
class ArenaZone:
    id: UUID
    name: str
    kind: ZoneKind
    shape: CircleShape | PolygonShape


@dataclass
class Arena:
    name: str
    boundary: list[GeoPoint]
    zones: list[ArenaZone] = field(default_factory=list)
    id: UUID | None = None


@dataclass(frozen=True)
class ArenaIssue:
    code: str
    name: str

    def as_tuple(self) -> tuple[str, str]:
        return self.code, self.name


def point_from_dict(data: dict[str, Any]) -> GeoPoint:
    return GeoPoint(lat=float(data["lat"]), lon=float(data["lon"]))


def arena_from_dict(data: dict[str, Any]) -> Arena:
    zones: list[ArenaZone] = []
    for raw in data.get("zones", []):
        shape_raw = raw["shape"]
        if shape_raw["type"] == "circle":
            shape: CircleShape | PolygonShape = CircleShape(
                center=point_from_dict(shape_raw["center"]),
                radius_m=float(shape_raw["radius_m"]),
            )
        else:
            shape = PolygonShape(vertices=[point_from_dict(v) for v in shape_raw["vertices"]])
        zones.append(
            ArenaZone(
                id=UUID(str(raw["id"])) if raw.get("id") else uuid4(),
                name=str(raw["name"]),
                kind=ZoneKind(raw["kind"]),
                shape=shape,
            )
        )
    arena_id = data.get("id")
    return Arena(
        id=UUID(str(arena_id)) if arena_id else None,
        name=str(data.get("name", "")),
        boundary=[point_from_dict(v) for v in data.get("boundary", [])],
        zones=zones,
    )


def arena_to_dict(arena: Arena) -> dict[str, Any]:
    zones = []
    for zone in arena.zones:
        if isinstance(zone.shape, CircleShape):
            shape = {
                "type": "circle",
                "center": {"lat": zone.shape.center.lat, "lon": zone.shape.center.lon},
                "radius_m": zone.shape.radius_m,
            }
        else:
            shape = {
                "type": "polygon",
                "vertices": [{"lat": v.lat, "lon": v.lon} for v in zone.shape.vertices],
            }
        zones.append(
            {
                "id": str(zone.id),
                "name": zone.name,
                "kind": zone.kind.value,
                "shape": shape,
            }
        )
    payload: dict[str, Any] = {
        "name": arena.name,
        "boundary": [{"lat": v.lat, "lon": v.lon} for v in arena.boundary],
        "zones": zones,
    }
    if arena.id:
        payload["id"] = str(arena.id)
    return payload


def clip_zone(zone: ArenaZone, play: list[GeoPoint]) -> ArenaZone | None:
    if isinstance(zone.shape, PolygonShape):
        if polygon_inside_play_area(zone.shape.vertices, play):
            return zone
        clipped = clip_polygon(zone.shape.vertices, play)
        if clipped is None:
            return None
        return ArenaZone(
            id=zone.id,
            name=zone.name,
            kind=zone.kind,
            shape=PolygonShape(vertices=clipped),
        )
    if circle_inside_play_area(zone.shape.center, zone.shape.radius_m, play):
        return zone
    ring = circle_sample_ring(zone.shape.center, zone.shape.radius_m)
    clipped = clip_polygon(ring, play)
    if clipped is None:
        return None
    return ArenaZone(
        id=zone.id,
        name=zone.name,
        kind=zone.kind,
        shape=PolygonShape(vertices=clipped),
    )


def clip_arena(arena: Arena) -> Arena:
    if len(arena.boundary) < 3:
        return arena
    clipped_zones: list[ArenaZone] = []
    for zone in arena.zones:
        clipped = clip_zone(zone, arena.boundary)
        if clipped is not None:
            clipped_zones.append(clipped)
    return Arena(
        id=arena.id,
        name=arena.name,
        boundary=arena.boundary,
        zones=clipped_zones,
    )


def validate_arena(arena: Arena) -> list[ArenaIssue]:
    issues: list[ArenaIssue] = []
    if len(arena.boundary) < 3:
        issues.append(ArenaIssue("play_area_too_small", "Play area"))
        return issues
    if self_intersects(arena.boundary):
        issues.append(ArenaIssue("self_intersection", "Play area"))
    if len(arena.zones) > 30:
        issues.append(ArenaIssue("too_many_zones", "Play area"))
    for zone in arena.zones:
        if isinstance(zone.shape, PolygonShape):
            if len(zone.shape.vertices) < 3 or len(zone.shape.vertices) > 100:
                issues.append(ArenaIssue("outside_play_area", zone.name))
                continue
            if self_intersects(zone.shape.vertices):
                issues.append(ArenaIssue("self_intersection", zone.name))
            if not polygon_inside_play_area(zone.shape.vertices, arena.boundary):
                issues.append(ArenaIssue("outside_play_area", zone.name))
        else:
            if zone.shape.radius_m < 2 or zone.shape.radius_m > 500:
                issues.append(ArenaIssue("outside_play_area", zone.name))
                continue
            if not circle_inside_play_area(zone.shape.center, zone.shape.radius_m, arena.boundary):
                issues.append(ArenaIssue("outside_play_area", zone.name))
    return issues
