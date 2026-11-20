import type { LatLon } from '../api/types'
import type { ResolvedPlayBoundary } from './arenaBoundary'

const METERS_PER_DEGREE = 111_320

function distanceM(a: LatLon, b: LatLon): number {
  const lat0 = ((a.lat + b.lat) / 2) * (Math.PI / 180)
  const north = (b.lat - a.lat) * METERS_PER_DEGREE
  const east = (b.lon - a.lon) * METERS_PER_DEGREE * Math.cos(lat0)
  return Math.hypot(east, north)
}

/** Ray-cast point-in-polygon for arena boundaries without a play circle. */
function pointInPolygon(point: LatLon, vertices: LatLon[]): boolean {
  let inside = false
  for (let i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
    const xi = vertices[i].lon
    const yi = vertices[i].lat
    const xj = vertices[j].lon
    const yj = vertices[j].lat
    const intersect =
      yi > point.lat !== yj > point.lat &&
      point.lon < ((xj - xi) * (point.lat - yi)) / (yj - yi + Number.EPSILON) + xi
    if (intersect) {
      inside = !inside
    }
  }
  return inside
}

export function pointInPlayArea(
  point: LatLon,
  boundary: ResolvedPlayBoundary | null,
): boolean {
  if (!boundary) {
    return false
  }
  if (boundary.kind === 'circle') {
    const d = distanceM(point, boundary.circle.center)
    return d <= boundary.circle.radius_m
  }
  return pointInPolygon(point, boundary.vertices)
}