import type L from 'leaflet'
import type { ResolvedPlayBoundary } from './arenaBoundary'

export type ArenaCircle = {
  center: { lat: number; lon: number }
  radius_m: number
}

function clearClamps(map: L.Map): void {
  // Clear any earlier clamp from a previous build still in memory during HMR.
  map.setMaxBounds(null as unknown as L.LatLngBounds)
  map.options.maxBoundsViscosity = 0
  map.setMinZoom(0)
  map.setMaxZoom(19)
}

function boundsForBoundary(
  boundary: ResolvedPlayBoundary | ArenaCircle,
  leaflet: typeof L,
): L.LatLngBounds {
  // Legacy callers still pass a bare circle.
  if ('center' in boundary && 'radius_m' in boundary && !('kind' in boundary)) {
    return leaflet
      .latLng(boundary.center.lat, boundary.center.lon)
      .toBounds(boundary.radius_m * 2.3)
  }
  const resolved = boundary as ResolvedPlayBoundary
  if (resolved.kind === 'circle') {
    return leaflet
      .latLng(resolved.circle.center.lat, resolved.circle.center.lon)
      .toBounds(resolved.circle.radius_m * 2.3)
  }
  const latLngs = resolved.vertices.map(
    (v) => [v.lat, v.lon] as [number, number],
  )
  return leaflet.latLngBounds(latLngs).pad(0.2)
}

/**
 * One-shot framing on the play area. Pan and zoom stay unbounded afterward —
 * clamping made every WebSocket view snap the camera back.
 */
export function fitArenaOnce(
  map: L.Map,
  boundary: ResolvedPlayBoundary | ArenaCircle,
  leaflet: typeof L,
): void {
  clearClamps(map)
  map.fitBounds(boundsForBoundary(boundary, leaflet), { animate: false })
}

export function recenterOnArena(
  map: L.Map,
  boundary: ResolvedPlayBoundary | ArenaCircle,
  leaflet: typeof L,
): void {
  map.fitBounds(boundsForBoundary(boundary, leaflet), { animate: true })
}
