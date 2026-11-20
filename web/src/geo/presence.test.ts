import { afterEach, describe, expect, it, vi } from 'vitest'
import { isUsablePresenceFix, startLivePresence } from './presence'
import type { GeoFix } from './watchVisible'

afterEach(() => {
  vi.useRealTimers()
})

describe('isUsablePresenceFix', () => {
  it('accepts a coarse but finite fix', () => {
    expect(
      isUsablePresenceFix(null, { lat: 40, lon: -75, accuracyM: 80 }, 1000),
    ).toBe(true)
  })

  it('rejects a non-finite fix', () => {
    expect(
      isUsablePresenceFix(null, { lat: Number.NaN, lon: -75, accuracyM: 10 }, 1000),
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
  it('holds the desk seed until GPS has had time to arrive', () => {
    vi.useFakeTimers()
    const onFix = vi.fn()
    const seed: GeoFix = { lat: 40.1, lon: -75.1, accuracyM: 12 }
    const stop = startLivePresence({
      onFix,
      seedFix: seed,
      seedWaitMs: 8000,
      heartbeatMs: 1000,
      watchLocation: () => () => undefined,
    })
    expect(onFix).not.toHaveBeenCalled()
    vi.advanceTimersByTime(7999)
    expect(onFix).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    expect(onFix).toHaveBeenCalledWith({ ...seed, reset: false })
    onFix.mockClear()
    vi.advanceTimersByTime(1000)
    expect(onFix).toHaveBeenCalledWith({ ...seed, reset: false })
    stop()
  })

  it('adopts a coarse phone fix and does not publish the seed', () => {
    vi.useFakeTimers()
    const onFix = vi.fn()
    let pushFix: ((fix: GeoFix) => void) | undefined
    const seed: GeoFix = { lat: 40.1, lon: -75.1, accuracyM: 12 }
    const stop = startLivePresence({
      onFix,
      seedFix: seed,
      seedWaitMs: 8000,
      heartbeatMs: 1000,
      watchLocation: (opts) => {
        pushFix = opts.onFix
        return () => undefined
      },
    })
    const phone: GeoFix = { lat: 40.2, lon: -75.2, accuracyM: 40 }
    pushFix!(phone)
    expect(onFix).toHaveBeenCalledWith({ ...phone, reset: false })
    onFix.mockClear()
    vi.advanceTimersByTime(8000)
    expect(onFix).not.toHaveBeenCalledWith(expect.objectContaining({ lat: seed.lat }))
    stop()
  })

  it('sends one reset when a real fix replaces a published seed', () => {
    vi.useFakeTimers()
    const onFix = vi.fn()
    let pushFix: ((fix: GeoFix) => void) | undefined
    const seed: GeoFix = { lat: 40.1, lon: -75.1, accuracyM: 12 }
    const stop = startLivePresence({
      onFix,
      seedFix: seed,
      seedWaitMs: 1000,
      heartbeatMs: 10_000,
      watchLocation: (opts) => {
        pushFix = opts.onFix
        return () => undefined
      },
    })
    vi.advanceTimersByTime(1000)
    expect(onFix).toHaveBeenCalledWith({ ...seed, reset: false })
    onFix.mockClear()
    const phone: GeoFix = { lat: 40.2, lon: -75.2, accuracyM: 40 }
    pushFix!(phone)
    expect(onFix).toHaveBeenCalledWith({ ...phone, reset: true })
    onFix.mockClear()
    pushFix!({ lat: 40.20001, lon: -75.2, accuracyM: 15 })
    expect(onFix).toHaveBeenCalledWith(
      expect.objectContaining({ lat: 40.20001, reset: false }),
    )
    stop()
  })
})
