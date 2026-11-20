import type { LatLon } from '../api/types'

export const PIN_GLIDE_MS = 400

export type GlideProgress = {
  t: number
  point: LatLon
}

/** Linear interpolation in lat/lon over durationMs (simple planer glide for pins). */
export function glidePoint(
  from: LatLon,
  to: LatLon,
  elapsedMs: number,
  durationMs = PIN_GLIDE_MS,
): LatLon {
  const t = Math.min(1, Math.max(0, elapsedMs / durationMs))
  return {
    lat: from.lat + (to.lat - from.lat) * t,
    lon: from.lon + (to.lon - from.lon) * t,
  }
}