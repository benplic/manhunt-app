import { afterEach, describe, expect, it, vi } from 'vitest'
import { isUsablePresenceFix, startLivePresence } from './presence'
import type { GeoFix } from './watchVisible'

afterEach(() => {
  vi.useRealTimers()
})

describe('isUsablePresenceFix', () => {
  it('rejects accuracy worse than 30 m', () => {
    expect(
      isUsablePresenceFix(null, { lat: 40, lon: -75, accuracyM: 40 }, 1000),
    ).toBe(false)
  })

  it('rejects a teleport hop', () => {
    const prev: GeoFix = { lat: 40, lon: -75, accuracyM: 10 }
    // ~1 km north in one second — server would call this too fast.
    const next: GeoFix = { lat: 40.009, lon: -75, accuracyM: 10 }
    expect(isUsablePresenceFix(prev, next, 1000)).toBe(false)
  })

  it('keeps a short walk', () => {
    const prev: GeoFix = { lat: 40, lon: -75, accuracyM: 10 }
    const next: GeoFix = { lat: 40.00005, lon: -75, accuracyM: 10 }
    expect(isUsablePresenceFix(prev, next, 2000)).toBe(true)
  })
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

  it('ignores ±40 m GPS and keeps heartbeating the seed', () => {
    vi.useFakeTimers()
    const onFix = vi.fn()
    const onError = vi.fn()
    let pushFix: ((fix: GeoFix) => void) | undefined
    const seed: GeoFix = { lat: 40.1, lon: -75.1, accuracyM: 12 }
    const stop = startLivePresence({
      onFix,
      onError,
      seedFix: seed,
      heartbeatMs: 1000,
      watchLocation: (opts) => {
        pushFix = opts.onFix
        return () => undefined
      },
    })
    onFix.mockClear()
    pushFix!({ lat: 40.11, lon: -75.11, accuracyM: 40 })
    expect(onError).toHaveBeenCalled()
    // Fuzzy fix must not be forwarded.
    expect(onFix).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1000)
    expect(onFix).toHaveBeenCalledWith(seed)
    stop()
  })
})
