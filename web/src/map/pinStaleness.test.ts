import { describe, expect, it } from 'vitest'
import {
  barsForAge,
  pinOpacity,
  pinOpacityForBars,
  STALE_AFTER_INTERVALS,
} from './pinStaleness'

const NOW = Date.parse('2026-11-24T20:00:00Z')
const atMs = (secondsAgo: number) => NOW - secondsAgo * 1000

describe('pinStaleness', () => {
  it('keeps stale after two ping intervals', () => {
    expect(STALE_AFTER_INTERVALS).toBe(2)
    const interval = 60
    expect(barsForAge(60, interval, false)).toBe(4)
    expect(barsForAge(120, interval, false)).toBe(3)
    expect(barsForAge(121, interval, false)).toBe(2)
  })

  it('maps bars to pin opacity', () => {
    expect(pinOpacityForBars(4)).toBe(1)
    expect(pinOpacityForBars(2)).toBe(0.5)
    expect(pinOpacityForBars(1)).toBe(0.45)
  })

  it('dims a stale fix on the map', () => {
    expect(
      pinOpacity({
        fixAtMs: atMs(150),
        status: 'active',
        pingIntervalS: 60,
        nowMs: NOW,
      }),
    ).toBe(0.5)
  })

  it('keeps signal-lost pins faint even when recent', () => {
    expect(
      pinOpacity({
        fixAtMs: atMs(5),
        status: 'signal_lost',
        pingIntervalS: 60,
        nowMs: NOW,
      }),
    ).toBe(0.45)
  })
})