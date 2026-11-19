import { describe, expect, it, vi } from 'vitest'
import { fitArenaOnce, recenterOnArena } from './arenaCamera'

function fakeLeaflet() {
  const bounds = { pad: vi.fn().mockReturnThis() }
  return {
    latLng: vi.fn(() => ({
      toBounds: vi.fn(() => bounds),
    })),
  }
}

describe('arenaCamera', () => {
  it('fits once and clears pan/zoom clamps', () => {
    const leaflet = fakeLeaflet()
    const map = {
      fitBounds: vi.fn(),
      setMaxBounds: vi.fn(),
      setMinZoom: vi.fn(),
      setMaxZoom: vi.fn(),
      options: { maxBoundsViscosity: 1 } as { maxBoundsViscosity?: number },
    }
    fitArenaOnce(
      map as never,
      { center: { lat: 40, lon: -75 }, radius_m: 400 },
      leaflet as never,
    )
    expect(map.setMaxBounds).toHaveBeenCalledWith(null)
    expect(map.setMinZoom).toHaveBeenCalledWith(0)
    expect(map.options.maxBoundsViscosity).toBe(0)
    expect(map.fitBounds).toHaveBeenCalled()
  })

  it('recenters without clamping', () => {
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
