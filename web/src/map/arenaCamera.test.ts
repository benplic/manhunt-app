import { describe, expect, it, vi } from 'vitest'
import { fitArenaOnce, recenterOnArena } from './arenaCamera'

function fakeLeaflet() {
  const padded = { kind: 'padded' }
  const polyBounds = { pad: vi.fn(() => padded) }
  return {
    latLng: vi.fn(() => ({
      toBounds: vi.fn(() => ({ kind: 'circleBounds' })),
    })),
    latLngBounds: vi.fn(() => polyBounds),
  }
}

describe('arenaCamera', () => {
  it('fits a circle once and clears pan/zoom clamps', () => {
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
      { kind: 'circle', circle: { center: { lat: 40, lon: -75 }, radius_m: 400 } },
      leaflet as never,
    )
    expect(map.setMaxBounds).toHaveBeenCalledWith(null)
    expect(map.setMinZoom).toHaveBeenCalledWith(0)
    expect(map.options.maxBoundsViscosity).toBe(0)
    expect(map.fitBounds).toHaveBeenCalledWith(
      { kind: 'circleBounds' },
      { animate: false },
    )
  })

  it('fits a polygon with padded vertex bounds', () => {
    const leaflet = fakeLeaflet()
    const map = {
      fitBounds: vi.fn(),
      setMaxBounds: vi.fn(),
      setMinZoom: vi.fn(),
      setMaxZoom: vi.fn(),
      options: {} as { maxBoundsViscosity?: number },
    }
    const vertices = [
      { lat: 40, lon: -74 },
      { lat: 40.1, lon: -74 },
      { lat: 40.1, lon: -73.9 },
    ]
    fitArenaOnce(map as never, { kind: 'polygon', vertices }, leaflet as never)
    expect(leaflet.latLngBounds).toHaveBeenCalledWith([
      [40, -74],
      [40.1, -74],
      [40.1, -73.9],
    ])
    expect(map.fitBounds).toHaveBeenCalledWith({ kind: 'padded' }, { animate: false })
  })

  it('recenters a polygon without clamping', () => {
    const leaflet = fakeLeaflet()
    const map = { fitBounds: vi.fn() }
    recenterOnArena(
      map as never,
      {
        kind: 'polygon',
        vertices: [
          { lat: 1, lon: 2 },
          { lat: 1.1, lon: 2 },
          { lat: 1.1, lon: 2.1 },
        ],
      },
      leaflet as never,
    )
    expect(map.fitBounds).toHaveBeenCalledWith({ kind: 'padded' }, { animate: true })
  })

  it('still accepts a legacy bare circle argument', () => {
    const leaflet = fakeLeaflet()
    const map = {
      fitBounds: vi.fn(),
      setMaxBounds: vi.fn(),
      setMinZoom: vi.fn(),
      setMaxZoom: vi.fn(),
      options: {} as { maxBoundsViscosity?: number },
    }
    fitArenaOnce(
      map as never,
      { center: { lat: 40, lon: -75 }, radius_m: 400 },
      leaflet as never,
    )
    expect(map.fitBounds).toHaveBeenCalledWith(
      { kind: 'circleBounds' },
      { animate: false },
    )
  })
})
