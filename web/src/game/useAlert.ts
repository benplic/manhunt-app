import { useCallback, useEffect, useRef, useState } from 'react'
import { AlertQueue, type LiveAlert, type ShownAlert } from './alertQueue'

/**
 * Drives an AlertQueue with a real timer. Returns what to render and a stable `enqueue`.
 *
 * - `paused`: true while the alert surface cannot be seen (a panel is open). The queue's
 *   clock stops, so an alert is never used up unseen.
 * - `now` is injectable so tests can use fake timers without touching the wall clock.
 */
export function useAlert(
  options: { paused?: boolean; now?: () => number } = {},
): {
  shown: ShownAlert | null
  enqueue: (alert: LiveAlert) => void
} {
  const { paused = false, now = Date.now } = options
  const [queue] = useState(() => new AlertQueue())
  const [shown, setShown] = useState<ShownAlert | null>(null)
  const timerRef = useRef<number | null>(null)
  const nowRef = useRef(now)
  useEffect(() => {
    nowRef.current = now
  }, [now])

  // Publish the queue's state and (re)arm the single timer. It owns everything it needs,
  // so any caller, in any effect order, gets a working timer.
  const sync = useCallback(
    function sync() {
      setShown(queue.current)
      if (timerRef.current != null) {
        window.clearTimeout(timerRef.current)
        timerRef.current = null
      }
      const wakeAt = queue.nextWakeAt()
      if (wakeAt == null) {
        return
      }
      timerRef.current = window.setTimeout(
        () => {
          timerRef.current = null
          queue.advance(nowRef.current())
          sync()
        },
        Math.max(0, wakeAt - nowRef.current()),
      )
    },
    [queue],
  )

  const enqueue = useCallback(
    (alert: LiveAlert) => {
      queue.enqueue(alert, nowRef.current())
      sync()
    },
    [queue, sync],
  )

  // The clock runs only while the surface is open AND the tab is visible. Nothing is
  // dropped while it is stopped: alerts queue, and the showing one restarts on return.
  const pausedRef = useRef(paused)
  const applyHold = useCallback(() => {
    const unseen = pausedRef.current || document.visibilityState === 'hidden'
    if (unseen) {
      queue.hold(nowRef.current())
    } else {
      queue.release(nowRef.current())
    }
    sync()
  }, [queue, sync])

  useEffect(() => {
    pausedRef.current = paused
    applyHold()
  }, [paused, applyHold])

  useEffect(() => {
    document.addEventListener('visibilitychange', applyHold)
    // Re-arm after a StrictMode unmount/mount, whose cleanup cleared the timer.
    sync()
    return () => {
      document.removeEventListener('visibilitychange', applyHold)
      if (timerRef.current != null) {
        window.clearTimeout(timerRef.current)
        timerRef.current = null
      }
    }
  }, [applyHold, sync])

  return { shown, enqueue }
}
