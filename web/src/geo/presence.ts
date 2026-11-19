import type { GeoFix } from './watchVisible'
import { watchVisibleLocation } from './watchVisible'

/** Match server ACCURACY_CUTOFF_M — fuzzier than this is useless for tags/OOB. */
export const PRESENCE_ACCURACY_MAX_M = 30
const MAX_SPEED_MPS = 8
const JUMP_SLACK_M = 40
const METERS_PER_DEGREE = 111_320

export type PresenceOptions = {
  onFix: (fix: GeoFix) => void
  onError?: (message: string) => void
  /** Used when the browser never delivers GPS (common on desktop). */
  seedFix?: GeoFix | null
  /** How often to re-send the last good fix while the tab is visible. */
  heartbeatMs?: number
  watchLocation?: typeof watchVisibleLocation
  getVisibility?: () => DocumentVisibilityState
  now?: () => number
}

function distanceM(a: GeoFix, b: GeoFix): number {
  const lat0 = ((a.lat + b.lat) / 2) * (Math.PI / 180)
  const north = (b.lat - a.lat) * METERS_PER_DEGREE
  const east = (b.lon - a.lon) * METERS_PER_DEGREE * Math.cos(lat0)
  return Math.hypot(east, north)
}

/** True when the server would accept this hop (not a teleport, not too fuzzy). */
export function isUsablePresenceFix(
  prev: GeoFix | null,
  next: GeoFix,
  elapsedMs: number,
): boolean {
  if (next.accuracyM > PRESENCE_ACCURACY_MAX_M) {
    return false
  }
  if (!prev) {
    return true
  }
  const allowed = MAX_SPEED_MPS * Math.max(elapsedMs, 0) / 1000 + JUMP_SLACK_M
  return distanceM(prev, next) <= allowed
}

/**
 * Keep the server silence clock fresh while this tab is visible.
 *
 * Mac CoreLocation-via-browser often reports ±40 m and jumps. Production rejects
 * those teleports; without a heartbeat the host goes dark and (on the old win
 * rule) the hunt ends as “All hiders were tagged.”
 */
export function startLivePresence(options: PresenceOptions): () => void {
  const heartbeatMs = options.heartbeatMs ?? 5_000
  const getVisibility = options.getVisibility ?? (() => document.visibilityState)
  const now = options.now ?? (() => Date.now())
  const watch = options.watchLocation ?? watchVisibleLocation

  let lastGood: GeoFix | null = null
  let lastGoodAt = 0
  let heartbeatId: ReturnType<typeof setInterval> | null = null
  let warnedFuzzy = false

  function adopt(fix: GeoFix) {
    lastGood = fix
    lastGoodAt = now()
    options.onFix(fix)
  }

  function tickHeartbeat() {
    if (getVisibility() !== 'visible' || !lastGood) {
      return
    }
    options.onFix(lastGood)
  }

  function startHeartbeat() {
    if (heartbeatId !== null) {
      return
    }
    heartbeatId = setInterval(tickHeartbeat, heartbeatMs)
  }

  function stopHeartbeat() {
    if (heartbeatId !== null) {
      clearInterval(heartbeatId)
      heartbeatId = null
    }
  }

  if (options.seedFix && options.seedFix.accuracyM <= PRESENCE_ACCURACY_MAX_M) {
    adopt(options.seedFix)
  }
  startHeartbeat()

  const stopWatch = watch({
    onFix: (fix) => {
      if (!isUsablePresenceFix(lastGood, fix, now() - lastGoodAt)) {
        if (!warnedFuzzy && fix.accuracyM > PRESENCE_ACCURACY_MAX_M) {
          warnedFuzzy = true
          options.onError?.(
            `GPS ±${Math.round(fix.accuracyM)} m is too fuzzy — holding a steady desk fix so you do not go dark.`,
          )
        }
        // Keep heartbeating lastGood; do not send the rejected hop.
        return
      }
      adopt(fix)
    },
    onError: (message) => {
      if (lastGood) {
        options.onError?.(
          'No live GPS — holding the last steady fix so you do not go dark. Fine for desk tests.',
        )
        options.onFix(lastGood)
        return
      }
      if (options.seedFix) {
        adopt(options.seedFix)
        options.onError?.(
          'No live GPS — holding the play-circle center so you do not go dark. Fine for desk tests.',
        )
        return
      }
      options.onError?.(message)
    },
    getVisibility,
  })

  const onVisibility = () => {
    if (getVisibility() === 'visible') {
      startHeartbeat()
      if (lastGood) {
        options.onFix(lastGood)
      }
    } else {
      stopHeartbeat()
    }
  }
  document.addEventListener('visibilitychange', onVisibility)

  return () => {
    document.removeEventListener('visibilitychange', onVisibility)
    stopHeartbeat()
    stopWatch()
  }
}
