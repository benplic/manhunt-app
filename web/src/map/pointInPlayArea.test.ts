import { describe, expect, it } from 'vitest'
import { pointInPlayArea } from './pointInPlayArea'

describe('pointInPlayArea', () => {
  it('accepts points inside a play circle', () => {
    expect(
      pointInPlayArea(
        { lat: 40.66, lon: -73.96 },
        {
          kind: 'circle',
          circle: { center: { lat: 40.66, lon: -73.96 }, radius_m: 400 },
        },
      ),
    ).toBe(true)
  })

  it('rejects points outside a play circle', () => {
    expect(
      pointInPlayArea(
        { lat: 40.7, lon: -73.96 },
        {
          kind: 'circle',
          circle: { center: { lat: 40.66, lon: -73.96 }, radius_m: 100 },
        },
      ),
    ).toBe(false)
  })
})