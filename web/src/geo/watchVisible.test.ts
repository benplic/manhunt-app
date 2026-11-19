import { afterEach, describe, expect, it, vi } from 'vitest'
import { watchVisibleLocation } from './watchVisible'

describe('watchVisibleLocation', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('starts watch when visible and clears when hidden', () => {
    let visibility: DocumentVisibilityState = 'visible'
    const clearWatch = vi.fn()
    const watchPosition = vi.fn().mockReturnValue(7)
    const geo = { watchPosition, clearWatch } as unknown as Geolocation

    const stop = watchVisibleLocation({
      geolocation: geo,
      getVisibility: () => visibility,
      onFix: () => undefined,
    })

    expect(watchPosition).toHaveBeenCalledTimes(1)

    visibility = 'hidden'
    document.dispatchEvent(new Event('visibilitychange'))
    expect(clearWatch).toHaveBeenCalledWith(7)

    visibility = 'visible'
    document.dispatchEvent(new Event('visibilitychange'))
    expect(watchPosition).toHaveBeenCalledTimes(2)

    stop()
    expect(clearWatch).toHaveBeenCalled()
  })
})
