/**
 * Keep the screen awake during a live hunt. Safari 16.4+ supports Wake Lock.
 * Returns a release function. No-ops when the API is missing.
 */
export async function requestHuntWakeLock(): Promise<() => void> {
  if (typeof navigator === 'undefined' || !('wakeLock' in navigator)) {
    return () => undefined
  }
  let sentinel: WakeLockSentinel | null = null
  try {
    sentinel = await navigator.wakeLock.request('screen')
  } catch {
    // TODO: surface denied wake lock once we have a non-spammy banner.
    return () => undefined
  }

  const onVisibility = () => {
    if (document.visibilityState === 'visible' && sentinel?.released !== false) {
      void navigator.wakeLock.request('screen').then((next) => {
        sentinel = next
      }).catch(() => {
        // Permission or focus was lost; GPS hint already covers this.
      })
    }
  }
  document.addEventListener('visibilitychange', onVisibility)

  return () => {
    document.removeEventListener('visibilitychange', onVisibility)
    void sentinel?.release()
  }
}
