"""Flat-earth geometry. 111,320 m/degree, never haversine."""

from __future__ import annotations

import math
from dataclasses import dataclass

from shapely.geometry import Point
from shapely.geometry import Polygon as ShapelyPolygon

METERS_PER_DEGREE = 111_320.0
ACCURACY_CUTOFF_M = 30.0


@dataclass(frozen=True, slots=True)
class GeoPoint:
    lat: float
    lon: float


def distance_m(a: GeoPoint, b: GeoPoint) -> float:
    lat0 = math.radians((a.lat + b.lat) / 2)
    dy = (b.lat - a.lat) * METERS_PER_DEGREE
    dx = (b.lon - a.lon) * METERS_PER_DEGREE * math.cos(lat0)
    return math.hypot(dx, dy)


def offset_m(origin: GeoPoint, north_m: float, east_m: float) -> GeoPoint:
    lat0 = math.radians(origin.lat)
    dlat = north_m / METERS_PER_DEGREE
    dlon = east_m / (METERS_PER_DEGREE * max(math.cos(lat0), 1e-9))
    return GeoPoint(lat=origin.lat + dlat, lon=origin.lon + dlon)


def _lat0(points: list[GeoPoint]) -> float:
    return points[0].lat if points else 0.0


def _xy(point: GeoPoint, lat0: float) -> tuple[float, float]:
    return (
        point.lon * METERS_PER_DEGREE * math.cos(math.radians(lat0)),
        point.lat * METERS_PER_DEGREE,
    )


def _to_shapely(vertices: list[GeoPoint]) -> ShapelyPolygon:
    lat0 = _lat0(vertices)
    coords = [_xy(v, lat0) for v in vertices]
    if coords[0] != coords[-1]:
        coords.append(coords[0])
    return ShapelyPolygon(coords)


def contains(point: GeoPoint, vertices: list[GeoPoint]) -> bool:
    """True if the polygon covers the point, including the boundary."""
    if len(vertices) < 3:
        return False
    poly = _to_shapely(vertices)
    lat0 = _lat0(vertices)
    return bool(poly.covers(Point(_xy(point, lat0))))


def self_intersects(vertices: list[GeoPoint]) -> bool:
    if len(vertices) < 4:
        return False
    poly = _to_shapely(vertices)
    return not poly.is_valid


def distance_outside_m(point: GeoPoint, vertices: list[GeoPoint]) -> float:
    if contains(point, vertices):
        return 0.0
    poly = _to_shapely(vertices)
    lat0 = _lat0(vertices)
    return float(Point(_xy(point, lat0)).distance(poly.boundary))


def is_confidently_outside(
    point: GeoPoint,
    accuracy_m: float,
    vertices: list[GeoPoint],
    margin_m: float,
) -> bool:
    if accuracy_m > ACCURACY_CUTOFF_M:
        return False
    return distance_outside_m(point, vertices) > accuracy_m + margin_m


def circle_covers(center: GeoPoint, radius_m: float, point: GeoPoint) -> bool:
    return distance_m(center, point) <= radius_m


def circle_inside_play_area(
    center: GeoPoint, radius_m: float, play_vertices: list[GeoPoint]
) -> bool:
    if not contains(center, play_vertices):
        return False
    return distance_outside_to_interior_edge(center, play_vertices) >= radius_m - 0.01


def distance_outside_to_interior_edge(point: GeoPoint, vertices: list[GeoPoint]) -> float:
    """Distance from an interior point to the nearest edge. 0 if outside."""
    if not contains(point, vertices):
        return 0.0
    poly = _to_shapely(vertices)
    lat0 = _lat0(vertices)
    return float(Point(_xy(point, lat0)).distance(poly.boundary))


def polygon_inside_play_area(zone: list[GeoPoint], play: list[GeoPoint]) -> bool:
    if len(zone) < 3 or len(play) < 3:
        return False
    play_poly = _to_shapely(play)
    zone_poly = _to_shapely(zone)
    if zone_poly.is_empty:
        return False
    return bool(play_poly.covers(zone_poly))
