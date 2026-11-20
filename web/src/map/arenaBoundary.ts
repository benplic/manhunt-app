import type { LatLon } from '../api/types'
import type { ArenaCircle } from './arenaCamera'

export type PlayArena = {
  boundary?: LatLon[] | null
  boundary_circle?: {
    center: LatLon
    radius_m: number
  } | null
} | null

export type ResolvedPlayBoundary =
  | { kind: 'circle'; circle: ArenaCircle }
  | { kind: 'polygon'; vertices: LatLon[] }

/** Circle wins when present (matches iOS HuntMap). Else polygon if ≥3 verts. */
export function resolvePlayBoundary(arena: PlayArena): ResolvedPlayBoundary | null {
  const circle = arena?.boundary_circle
  if (
    circle &&
    Number.isFinite(circle.radius_m) &&
    circle.radius_m > 0 &&
    Number.isFinite(circle.center.lat) &&
    Number.isFinite(circle.center.lon)
  ) {
    return {
      kind: 'circle',
      circle: {
        center: { lat: circle.center.lat, lon: circle.center.lon },
        radius_m: circle.radius_m,
      },
    }
  }
  const boundary = arena?.boundary ?? []
  if (boundary.length >= 3) {
    return { kind: 'polygon', vertices: boundary }
  }
  return null
}

/** Stable identity so LiveMap re-fits only when the play area changes. */
export function arenaIdentityKey(resolved: ResolvedPlayBoundary | null): string {
  if (!resolved) {
    return ''
  }
  if (resolved.kind === 'circle') {
    const { center, radius_m } = resolved.circle
    return `circle:${center.lat},${center.lon},${radius_m}`
  }
  return `polygon:${resolved.vertices.map((v) => `${v.lat},${v.lon}`).join('|')}`
}

export function centroid(vertices: LatLon[]): LatLon | null {
  if (vertices.length === 0) {
    return null
  }
  let lat = 0
  let lon = 0
  for (const v of vertices) {
    lat += v.lat
    lon += v.lon
  }
  return { lat: lat / vertices.length, lon: lon / vertices.length }
}
