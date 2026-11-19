import { describe, expect, it } from 'vitest'
import { isAccuracyTooFuzzy, localAccuracyBlockMessage } from './tagErrors'

describe('tagErrors', () => {
  it('treats accuracy over 30 m as fuzzy', () => {
    expect(isAccuracyTooFuzzy(31)).toBe(true)
    expect(isAccuracyTooFuzzy(30)).toBe(false)
    expect(isAccuracyTooFuzzy(null)).toBe(true)
  })

  it('mentions the meter reading in the local block message', () => {
    expect(localAccuracyBlockMessage(42)).toContain('42')
  })
})
