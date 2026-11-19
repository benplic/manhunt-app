import type L from 'leaflet'

export type ArenaCircle = {
  center: { lat: number; lon: number }
  radius_m: number
}

/**
 * Fit the play circle, then clamp pan/zoom so phones cannot wander miles away.
 * Padding keeps a little street context around the yellow line.
 */
export function fitAndClampToArena(
  map: L.Map,
  circle: ArenaCircle,
  leaflet: typeof L,
): void {
  // Diameter * 1.15 → slight margin outside the yellow line.
  const viewBounds = leaflet
    .latLng(circle.center.lat, circle.center.lon)
    .toBounds(circle.radius_m * 2.3)
  map.fitBounds(viewBounds, { animate: false })
  // Harder pan clamp than the view fit so a fling cannot leave the arena.
  const panBounds = leaflet
    .latLng(circle.center.lat, circle.center.lon)
    .toBounds(circle.radius_m * 2.8)
  map.setMaxBounds(panBounds)
  map.options.maxBoundsViscosity = 1
  const fitZoom = map.getBoundsZoom(viewBounds)
  // Allow one notch of zoom-out for context; block regional zoom-outs.
  map.setMinZoom(Math.max(fitZoom - 1, 13))
  map.setMaxZoom(19)
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
