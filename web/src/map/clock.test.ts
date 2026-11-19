import { describe, expect, it } from 'vitest'
import { formatClock } from './clock'

describe('formatClock', () => {
  it('formats minutes and seconds', () => {
    expect(formatClock(125)).toBe('2:05')
    expect(formatClock(60)).toBe('1:00')
    expect(formatClock(0)).toBe('0:00')
  })

  it('handles missing values', () => {
    expect(formatClock(null)).toBe('--:--')
    expect(formatClock(undefined)).toBe('--:--')
  })
})
