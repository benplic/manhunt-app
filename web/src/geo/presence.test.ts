import { afterEach, describe, expect, it, vi } from 'vitest'
import { startLivePresence } from './presence'
import type { GeoFix } from './watchVisible'

afterEach(() => {
  vi.useRealTimers()
})

describe('startLivePresence', () => {
  it('seeds and heartbeats when GPS never arrives', () => {
    vi.useFakeTimers()
    const onFix = vi.fn()
    const seed: GeoFix = { lat: 40.1, lon: -75.1, accuracyM: 12 }
    const stop = startLivePresence({
      onFix,
      seedFix: seed,
      heartbeatMs: 1000,
      watchLocation: () => () => undefined,
    })
    expect(onFix).toHaveBeenCalledWith(seed)
    onFix.mockClear()
    vi.advanceTimersByTime(1000)
    expect(onFix).toHaveBeenCalledWith(seed)
    stop()
  })

  it('prefers live GPS over the seed after the first fix', () => {
    vi.useFakeTimers()
    const onFix = vi.fn()
    let pushFix: ((fix: GeoFix) => void) | undefined
    const stop = startLivePresence({
      onFix,
      seedFix: { lat: 1, lon: 1, accuracyM: 20 },
      heartbeatMs: 1000,
      watchLocation: (opts) => {
        pushFix = opts.onFix
        return () => undefined
      },
    })
    expect(pushFix).toBeTypeOf('function')
    pushFix!({ lat: 2, lon: 2, accuracyM: 5 })
    onFix.mockClear()
    vi.advanceTimersByTime(1000)
    expect(onFix).toHaveBeenCalledWith({ lat: 2, lon: 2, accuracyM: 5 })
    stop()
  })
})
