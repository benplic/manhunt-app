import type { GeoFix } from './watchVisible'
import { watchVisibleLocation } from './watchVisible'

/** How long to wait for a real fix before publishing a desk seed. */
export const SEED_WAIT_MS = 8_000
const MAX_SPEED_MPS = 8
const JUMP_SLACK_M = 40
const METERS_PER_DEGREE = 111_320

/** A fix plus whether the server should skip the speed check once. */
export type PresenceFix = GeoFix & { reset: boolean }

export type PresenceOptions = {
  onFix: (fix: PresenceFix) => void
  onError?: (message: string) => void
  /** Used when the browser never delivers GPS (common on desktop). */
  seedFix?: GeoFix | null
  /** Delay before the desk seed is published. A real fix cancels it. */
  seedWaitMs?: number
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

/** True when this hop is finite and not a teleport. Coarse accuracy is kept. */
export function isUsablePresenceFix(
  prev: GeoFix | null,
  next: GeoFix,
  elapsedMs: number,
): boolean {
  if (
    !Number.isFinite(next.lat) ||
    !Number.isFinite(next.lon) ||
    !Number.isFinite(next.accuracyM) ||
    next.accuracyM < 0
  ) {
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
 * Do not publish a desk seed until GPS fails or the wait expires. A phone
 * whose first sample is coarse must still move the pin off the play-circle
 * center, or the other client draws the wrong place.
 */
export function startLivePresence(options: PresenceOptions): () => void {
  const heartbeatMs = options.heartbeatMs ?? 5_000
  const seedWaitMs = options.seedWaitMs ?? SEED_WAIT_MS
  const getVisibility = options.getVisibility ?? (() => document.visibilityState)
  const now = options.now ?? (() => Date.now())
  const watch = options.watchLocation ?? watchVisibleLocation

  let lastGood: GeoFix | null = null
  let lastGoodAt = 0
  let heartbeatId: ReturnType<typeof setInterval> | null = null
  let seedTimer: ReturnType<typeof setTimeout> | null = null
  /** True while the published pin is the synthetic desk seed. */
  let seeded = false
  let resetSent = false

  function adopt(fix: GeoFix, reset: boolean) {
    lastGood = fix
    lastGoodAt = now()
    options.onFix({ ...fix, reset })
  }

  function clearSeedTimer() {
    if (seedTimer !== null) {
      clearTimeout(seedTimer)
      seedTimer = null
    }
  }

  function publishSeed(message: string) {
    if (!options.seedFix || lastGood) {
      return
    }
    seeded = true
    adopt(options.seedFix, false)
    options.onError?.(message)
  }

  function armSeed() {
    if (!options.seedFix || seedTimer !== null || lastGood) {
      return
    }
    seedTimer = setTimeout(() => {
      seedTimer = null
      publishSeed('No live GPS — holding the play-circle center so you do not go dark. Fine for desk tests.')
    }, seedWaitMs)
  }

  function tickHeartbeat() {
    if (getVisibility() !== 'visible' || !lastGood) {
      return
    }
    options.onFix({ ...lastGood, reset: false })
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

  armSeed()
  startHeartbeat()

  const stopWatch = watch({
    onFix: (fix) => {
      // Drop a non-finite sample without cancelling the desk-seed wait.
      if (!isUsablePresenceFix(null, fix, 0)) {
        return
      }
      clearSeedTimer()
      if (seeded && lastGood) {
        seeded = false
        const reset = !resetSent
        resetSent = true
        adopt(fix, reset)
        return
      }
      if (!isUsablePresenceFix(lastGood, fix, now() - lastGoodAt)) {
        // Keep heartbeating lastGood; do not send the rejected hop.
        return
      }
      adopt(fix, false)
    },
    onError: (message) => {
      if (lastGood) {
        options.onError?.(
          'No live GPS — holding the last steady fix so you do not go dark. Fine for desk tests.',
        )
        options.onFix({ ...lastGood, reset: false })
        return
      }
      if (options.seedFix) {
        clearSeedTimer()
        publishSeed(
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
        options.onFix({ ...lastGood, reset: false })
      }
    } else {
      stopHeartbeat()
    }
  }
  document.addEventListener('visibilitychange', onVisibility)

  return () => {
    document.removeEventListener('visibilitychange', onVisibility)
    clearSeedTimer()
    stopHeartbeat()
    stopWatch()
  }
}
