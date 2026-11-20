import { describe, expect, it } from 'vitest'
import { glidePoint, PIN_GLIDE_MS } from './pinGlide'

describe('glidePoint', () => {
  it('returns the midpoint halfway through glide', () => {
    const mid = glidePoint(
      { lat: 0, lon: 0 },
      { lat: 10, lon: 20 },
      PIN_GLIDE_MS / 2,
    )
    expect(mid.lat).toBeCloseTo(5)
    expect(mid.lon).toBeCloseTo(10)
  })
})