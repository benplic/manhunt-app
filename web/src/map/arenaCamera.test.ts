import { describe, expect, it, vi } from 'vitest'
import { fitAndClampToArena, recenterOnArena } from './arenaCamera'

function fakeLeaflet() {
  const bounds = { pad: vi.fn().mockReturnThis() }
  return {
    latLng: vi.fn(() => ({
      toBounds: vi.fn(() => bounds),
    })),
  }
}

describe('arenaCamera', () => {
  it('fits, clamps pan, and sets a floor zoom', () => {
    const leaflet = fakeLeaflet()
    const map = {
      fitBounds: vi.fn(),
      setMaxBounds: vi.fn(),
      getBoundsZoom: vi.fn(() => 16),
      setMinZoom: vi.fn(),
      setMaxZoom: vi.fn(),
      options: {} as { maxBoundsViscosity?: number },
    }
    fitAndClampToArena(
      map as never,
      { center: { lat: 40, lon: -75 }, radius_m: 400 },
      leaflet as never,
    )
    expect(map.fitBounds).toHaveBeenCalled()
    expect(map.setMaxBounds).toHaveBeenCalled()
    expect(map.setMinZoom).toHaveBeenCalledWith(15)
    expect(map.setMaxZoom).toHaveBeenCalledWith(19)
    expect(map.options.maxBoundsViscosity).toBe(1)
  })

  it('recenters without changing clamp math', () => {
    const leaflet = fakeLeaflet()
    const map = { fitBounds: vi.fn() }
    recenterOnArena(
      map as never,
      { center: { lat: 40, lon: -75 }, radius_m: 400 },
      leaflet as never,
    )
    expect(map.fitBounds).toHaveBeenCalledWith(expect.anything(), { animate: true })
  })
})
