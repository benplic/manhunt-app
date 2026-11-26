import { act, renderHook } from '@testing-library/react'
import { StrictMode, useEffect } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ALERT_SHOW_MS, type LiveAlert } from './alertQueue'
import { useAlert } from './useAlert'

function alert(key: string, priority: LiveAlert['priority']): LiveAlert {
  return { key, text: key, priority, tone: 'info' }
}

/** jsdom has no tab switching, so set `document.visibilityState` and fire the event. */
function setVisibility(state: 'visible' | 'hidden') {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state })
  act(() => {
    document.dispatchEvent(new Event('visibilitychange'))
  })
}

describe('useAlert', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(0)
  })
  afterEach(() => {
    vi.useRealTimers()
    // Drop the per-test override so the jsdom default ('visible') applies again.
    Reflect.deleteProperty(document, 'visibilityState')
  })

  it('shows one alert for 4 seconds, then the next queued one, then nothing', () => {
    const { result } = renderHook(() => useAlert())

    act(() => {
      result.current.enqueue(alert('tag', 1))
      result.current.enqueue(alert('ping', 3))
    })
    expect(result.current.shown?.key).toBe('tag')

    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS - 1)
    })
    expect(result.current.shown?.key).toBe('tag')

    act(() => {
      vi.advanceTimersByTime(1)
    })
    expect(result.current.shown?.key).toBe('ping')

    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS)
    })
    expect(result.current.shown).toBeNull()
  })

  it('queues a lower-priority alert behind a higher one instead of skipping it', () => {
    const { result } = renderHook(() => useAlert())

    act(() => {
      result.current.enqueue(alert('oob', 1))
    })
    act(() => {
      vi.advanceTimersByTime(1000)
      result.current.enqueue(alert('ping', 3))
    })
    expect(result.current.shown?.key).toBe('oob')

    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS - 1000)
    })
    expect(result.current.shown?.key).toBe('ping')
  })

  it('resumes an interrupted alert for its full time', () => {
    const { result } = renderHook(() => useAlert())

    act(() => {
      result.current.enqueue(alert('dark', 2))
    })
    act(() => {
      vi.advanceTimersByTime(1000)
      result.current.enqueue(alert('tag', 1))
    })
    expect(result.current.shown?.key).toBe('tag')

    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS)
    })
    expect(result.current.shown?.key).toBe('dark')
    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS - 1)
    })
    expect(result.current.shown?.key).toBe('dark')
    act(() => {
      vi.advanceTimersByTime(1)
    })
    expect(result.current.shown).toBeNull()
  })

  it('stops the clock while the tab is hidden and loses nothing when it returns', () => {
    const { result } = renderHook(() => useAlert())
    act(() => {
      result.current.enqueue(alert('now', 1))
      for (const key of ['p1', 'p2', 'p3', 'p4', 'p5']) {
        result.current.enqueue(alert(key, 3))
      }
    })

    setVisibility('hidden')
    act(() => {
      vi.advanceTimersByTime(60_000)
    })
    expect(result.current.shown?.key).toBe('now')

    setVisibility('visible')
    expect(result.current.shown?.key).toBe('now')
    const seen = [result.current.shown?.key]
    for (let i = 0; i < 6; i += 1) {
      act(() => {
        vi.advanceTimersByTime(ALERT_SHOW_MS)
      })
      seen.push(result.current.shown?.key)
    }
    expect(seen).toEqual(['now', 'p1', 'p2', 'p3', 'p4', 'p5', undefined])
  })

  it('gives a new showId to a resumed alert', () => {
    const { result } = renderHook(() => useAlert())
    act(() => {
      result.current.enqueue(alert('dark', 2))
    })
    const first = result.current.shown?.showId
    act(() => {
      result.current.enqueue(alert('tag', 1))
    })
    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS)
    })
    expect(result.current.shown?.key).toBe('dark')
    expect(result.current.shown?.showId).not.toBe(first)
  })

  it('works when enqueue is called from a child effect before the hook effects ran', () => {
    function useBoth() {
      const alerts = useAlert()
      // Runs during the first commit, in the same pass as the hook's own effects.
      useEffect(() => {
        alerts.enqueue(alert('early', 1))
      }, [alerts.enqueue])
      return alerts
    }
    const { result } = renderHook(() => useBoth())
    expect(result.current.shown?.key).toBe('early')
    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS)
    })
    expect(result.current.shown).toBeNull()
  })

  it('still expires alerts under StrictMode double-mounting', () => {
    const { result } = renderHook(() => useAlert(), { wrapper: StrictMode })
    act(() => {
      result.current.enqueue(alert('a', 1))
      result.current.enqueue(alert('b', 3))
    })
    expect(result.current.shown?.key).toBe('a')
    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS)
    })
    expect(result.current.shown?.key).toBe('b')
    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS)
    })
    expect(result.current.shown).toBeNull()
  })

  it('holds the clock while paused and gives the alert its full time once visible', () => {
    const { result, rerender } = renderHook(({ paused }) => useAlert({ paused }), {
      initialProps: { paused: false },
    })
    act(() => {
      result.current.enqueue(alert('tag', 1))
      result.current.enqueue(alert('ping', 3))
    })

    rerender({ paused: true })
    act(() => {
      vi.advanceTimersByTime(60_000)
    })
    // Scores panel was open for a minute: the tag alert has not been used up.
    expect(result.current.shown?.key).toBe('tag')

    rerender({ paused: false })
    act(() => {
      vi.advanceTimersByTime(ALERT_SHOW_MS - 1)
    })
    expect(result.current.shown?.key).toBe('tag')
    act(() => {
      vi.advanceTimersByTime(1)
    })
    expect(result.current.shown?.key).toBe('ping')
  })

  it('clears its timer on unmount', () => {
    const { result, unmount } = renderHook(() => useAlert())
    act(() => {
      result.current.enqueue(alert('a', 1))
    })
    unmount()
    expect(vi.getTimerCount()).toBe(0)
  })
})
