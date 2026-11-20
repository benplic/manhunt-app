import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  ackSafetyDisclaimer,
  needsSafetyDisclaimer,
  resetSafetyDisclaimerForTests,
} from './safetyDisclaimer'

describe('safetyDisclaimer', () => {
  beforeEach(() => {
    resetSafetyDisclaimerForTests()
    localStorage.clear()
  })

  it('needs ack before the user continues', () => {
    expect(needsSafetyDisclaimer()).toBe(true)
  })

  it('clears after ack', () => {
    ackSafetyDisclaimer()
    expect(needsSafetyDisclaimer()).toBe(false)
  })

  it('keeps the ack in memory when localStorage is blocked', () => {
    const setItem = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('quota')
    })
    const getItem = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked')
    })
    try {
      expect(needsSafetyDisclaimer()).toBe(true)
      ackSafetyDisclaimer()
      expect(needsSafetyDisclaimer()).toBe(false)
    } finally {
      setItem.mockRestore()
      getItem.mockRestore()
    }
  })
})
