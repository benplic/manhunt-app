import { describe, expect, it } from 'vitest'
import {
  arenaRadiusError,
  ARENA_RADIUS_RANGE_MESSAGE,
  isValidArenaRadius,
  MAX_ARENA_RADIUS_M,
  MIN_ARENA_RADIUS_M,
} from './arenaRadius'

describe('arena radius cap', () => {
  it('is 30 m to 3,000 m, matching the server', () => {
    expect(MIN_ARENA_RADIUS_M).toBe(30)
    expect(MAX_ARENA_RADIUS_M).toBe(3000)
  })

  it.each([
    [29.99, false],
    [30, true],
    [2000, true],
    [2001, true],
    [3000, true],
    [3000.01, false],
    [3001, false],
    [0, false],
    [-50, false],
    [Number.NaN, false],
    [Number.POSITIVE_INFINITY, false],
  ])('radius %s valid=%s', (radius, valid) => {
    expect(isValidArenaRadius(radius)).toBe(valid)
    expect(arenaRadiusError(radius)).toBe(valid ? null : ARENA_RADIUS_RANGE_MESSAGE)
  })

  it('treats an empty number input (Number("")) as invalid', () => {
    expect(isValidArenaRadius(Number(''))).toBe(false)
  })
})
