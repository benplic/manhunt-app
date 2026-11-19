export type GeoFix = {
  lat: number
  lon: number
  accuracyM: number
}

export type WatchVisibleOptions = {
  onFix: (fix: GeoFix) => void
  onError?: (message: string) => void
  /** Injected for tests. Defaults to document.visibilityState. */
  getVisibility?: () => DocumentVisibilityState
  geolocation?: Geolocation
}

/**
 * Watch GPS only while the tab is visible. Safari may still suspend updates
 * when the screen locks — keep the screen on during a hunt.
 */
export function watchVisibleLocation(options: WatchVisibleOptions): () => void {
  const geo = options.geolocation ?? navigator.geolocation
  const getVisibility = options.getVisibility ?? (() => document.visibilityState)
  let watchId: number | null = null

  function stopWatch() {
    if (watchId !== null && geo) {
      geo.clearWatch(watchId)
      watchId = null
    }
  }

  function startWatch() {
    if (!geo || watchId !== null) {
      return
    }
    watchId = geo.watchPosition(
      (pos) => {
        options.onFix({
          lat: pos.coords.latitude,
          lon: pos.coords.longitude,
          accuracyM: pos.coords.accuracy,
        })
      },
      () => {
        options.onError?.('Location permission is required while the hunt is live.')
      },
      { enableHighAccuracy: true, maximumAge: 1000, timeout: 15000 },
    )
  }

  function sync() {
    if (getVisibility() === 'visible') {
      startWatch()
    } else {
      stopWatch()
    }
  }

  sync()
  const onVisibility = () => sync()
  document.addEventListener('visibilitychange', onVisibility)

  return () => {
    document.removeEventListener('visibilitychange', onVisibility)
    stopWatch()
  }
}
