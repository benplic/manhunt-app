import type { HintObject } from '../api/types'

const CARDINALS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'] as const

/** Eight compass points. 0 is north, bins are 45 degrees (same as iOS HintCopy). */
export function cardinal(degrees: number): string {
  const turn = ((degrees % 360) + 360) % 360
  const index = Math.floor((turn + 22.5) / 45) % 8
  return CARDINALS[index]
}

/**
 * Dock line for `you.hint`. The server sends a dict, not a string.
 * Rendering that dict as a React child unmounts the whole app (black screen).
 */
export function hintLine(role: string, hint: unknown): string | null {
  // Classic Seeker reveal is Off, so a hider with no payload keeps the old line.
  if (role === 'hider' && (hint == null || hint === '')) {
    return 'Warmth is hidden from you.'
  }
  if (hint == null || hint === '') {
    return null
  }
  if (typeof hint === 'string') {
    return hint
  }
  if (typeof hint !== 'object') {
    return null
  }
  if (role !== 'seeker' && role !== 'hider') {
    return 'Warmth is hidden from you.'
  }
  const payload = hint as HintObject
  if (!payload.band) {
    return role === 'hider' ? 'Warmth is hidden from you.' : 'No hint yet.'
  }
  const name = payload.name || (role === 'hider' ? 'A seeker' : 'A hider')
  const meters = payload.meters == null || Number.isNaN(Number(payload.meters)) ? '?' : String(payload.meters)
  if (payload.bearing_deg == null || Number.isNaN(Number(payload.bearing_deg))) {
    return `${name} is ${payload.band}, ${meters} m`
  }
  return `${name} is ${payload.band}, ${meters} m, ${cardinal(Number(payload.bearing_deg))}`
}
