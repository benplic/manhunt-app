import { afterEach, describe, expect, it, vi } from 'vitest'
import { requestHuntWakeLock } from './wakeLock'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('requestHuntWakeLock', () => {
  it('no-ops when Wake Lock API is missing', async () => {
    vi.stubGlobal('navigator', {})
    const release = await requestHuntWakeLock()
    expect(() => release()).not.toThrow()
  })

  it('requests and releases a screen lock', async () => {
    const release = vi.fn(async () => undefined)
    const request = vi.fn(async () => ({ release, released: false }))
    vi.stubGlobal('navigator', { wakeLock: { request } })
    const stop = await requestHuntWakeLock()
    expect(request).toHaveBeenCalledWith('screen')
    stop()
    expect(release).toHaveBeenCalled()
  })
})
