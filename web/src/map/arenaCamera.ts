import type L from 'leaflet'

export type ArenaCircle = {
  center: { lat: number; lon: number }
  radius_m: number
}

/**
 * One-shot framing on the play circle. Pan and zoom stay unbounded afterward —
 * clamping made every WebSocket view snap the camera back.
 */
export function fitArenaOnce(
  map: L.Map,
  circle: ArenaCircle,
  leaflet: typeof L,
): void {
  // Clear any earlier clamp from a previous build still in memory during HMR.
  map.setMaxBounds(null as unknown as L.LatLngBounds)
  map.options.maxBoundsViscosity = 0
  map.setMinZoom(0)
  map.setMaxZoom(19)
  const viewBounds = leaflet
    .latLng(circle.center.lat, circle.center.lon)
    .toBounds(circle.radius_m * 2.3)
  map.fitBounds(viewBounds, { animate: false })
}

export function recenterOnArena(
  map: L.Map,
  circle: ArenaCircle,
  leaflet: typeof L,
): void {
  const viewBounds = leaflet
    .latLng(circle.center.lat, circle.center.lon)
    .toBounds(circle.radius_m * 2.3)
  map.fitBounds(viewBounds, { animate: true })
}
