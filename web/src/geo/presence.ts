import type { GeoFix } from './watchVisible'
import { watchVisibleLocation } from './watchVisible'

export type PresenceOptions = {
  onFix: (fix: GeoFix) => void
  onError?: (message: string) => void
  /** Used when the browser never delivers GPS (common on desktop). */
  seedFix?: GeoFix | null
  /** How often to re-send the last fix while the tab is visible. */
  heartbeatMs?: number
  watchLocation?: typeof watchVisibleLocation
  getVisibility?: () => DocumentVisibilityState
  now?: () => number
}

/**
 * Keep the server silence clock fresh while this tab is visible.
 *
 * Mac / desktop Chrome often never fires watchPosition. Without a heartbeat the
 * host hider goes dark after ~45s and phones see “went dark” banners.
 */
export function startLivePresence(options: PresenceOptions): () => void {
  const heartbeatMs = options.heartbeatMs ?? 10_000
  const getVisibility = options.getVisibility ?? (() => document.visibilityState)
  const now = options.now ?? (() => Date.now())
  const watch = options.watchLocation ?? watchVisibleLocation

  let lastFix: GeoFix | null = options.seedFix ?? null
  let sawLiveGps = false
  let heartbeatId: ReturnType<typeof setInterval> | null = null

  function emit(fix: GeoFix) {
    lastFix = fix
    options.onFix(fix)
  }

  function tickHeartbeat() {
    if (getVisibility() !== 'visible' || !lastFix) {
      return
    }
    // Re-send the parked fix so signal_loss does not fire on a still phone.
    options.onFix(lastFix)
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

  // Seed immediately so the first 45s silence window never starts empty.
  if (lastFix) {
    emit(lastFix)
  }
  startHeartbeat()

  const stopWatch = watch({
    onFix: (fix) => {
      sawLiveGps = true
      emit(fix)
    },
    onError: (message) => {
      if (!sawLiveGps && options.seedFix) {
        options.onError?.(
          'No live GPS — holding the play-circle center so you do not go dark. Fine for desk tests; use a phone outside.',
        )
        emit(options.seedFix)
        return
      }
      options.onError?.(message)
    },
    getVisibility,
  })

  const onVisibility = () => {
    if (getVisibility() === 'visible') {
      startHeartbeat()
      if (lastFix) {
        options.onFix(lastFix)
      }
    } else {
      stopHeartbeat()
    }
  }
  document.addEventListener('visibilitychange', onVisibility)

  // Touch now so tests can assert without waiting a full interval.
  void now

  return () => {
    document.removeEventListener('visibilitychange', onVisibility)
    stopHeartbeat()
    stopWatch()
  }
}
