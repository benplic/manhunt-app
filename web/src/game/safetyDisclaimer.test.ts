import { beforeEach, describe, expect, it } from 'vitest'
import { ackSafetyDisclaimer, needsSafetyDisclaimer } from './safetyDisclaimer'

describe('safetyDisclaimer', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('needs ack before the user continues', () => {
    expect(needsSafetyDisclaimer()).toBe(true)
  })

  it('clears after ack', () => {
    ackSafetyDisclaimer()
    expect(needsSafetyDisclaimer()).toBe(false)
  })
})