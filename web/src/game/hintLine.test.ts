import { describe, expect, it } from 'vitest'
import { hintLine } from './hintLine'

describe('hintLine', () => {
  it('passes a string hint through', () => {
    expect(hintLine('seeker', 'Warm · 40 m')).toBe('Warm · 40 m')
  })

  it('formats the server hint object the way iOS does', () => {
    expect(
      hintLine('seeker', { band: 'hot', meters: 30, name: 'Riley', bearing_deg: 0 }),
    ).toBe('Riley is hot, 30 m, N')
    expect(
      hintLine('seeker', { band: 'burning', meters: 4, name: 'Jordan', bearing_deg: 90 }),
    ).toBe('Jordan is burning, 4 m, E')
  })

  it('omits bearing when the server left it out', () => {
    expect(hintLine('seeker', { band: 'warm', meters: 70, name: 'Riley' })).toBe(
      'Riley is warm, 70 m',
    )
  })

  it('does not return the raw object for a hider', () => {
    expect(hintLine('hider', { band: 'hot', meters: 30, name: 'Riley', bearing_deg: 0 })).toBe(
      'Warmth is hidden from you.',
    )
  })

  it('returns null when there is no hint', () => {
    expect(hintLine('seeker', null)).toBeNull()
    expect(hintLine('seeker', undefined)).toBeNull()
  })
})
