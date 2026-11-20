import { describe, expect, it, vi } from 'vitest'
import { releaseScanner } from './scannerRelease'

describe('releaseScanner', () => {
  it('stops only after start resolves', async () => {
    let resolveStart: () => void = () => undefined
    const start = new Promise<void>((resolve) => {
      resolveStart = resolve
    })
    const stop = vi.fn().mockResolvedValue(undefined)
    const released = releaseScanner(start, stop)
    expect(stop).not.toHaveBeenCalled()
    resolveStart()
    await released
    expect(stop).toHaveBeenCalledOnce()
  })

  it('does not stop when start fails', async () => {
    const stop = vi.fn().mockResolvedValue(undefined)
    await releaseScanner(Promise.reject(new Error('denied')), stop)
    expect(stop).not.toHaveBeenCalled()
  })
})
