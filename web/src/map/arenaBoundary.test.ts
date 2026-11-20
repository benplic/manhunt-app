import { describe, expect, it } from 'vitest'
import {
  arenaIdentityKey,
  centroid,
  resolvePlayBoundary,
} from './arenaBoundary'

describe('resolvePlayBoundary', () => {
  it('prefers a usable circle over polygon vertices', () => {
    const resolved = resolvePlayBoundary({
      boundary: [
        { lat: 40, lon: -74 },
        { lat: 40.1, lon: -74 },
        { lat: 40.1, lon: -73.9 },
      ],
      boundary_circle: { center: { lat: 40.05, lon: -73.95 }, radius_m: 400 },
    })
    expect(resolved).toEqual({
      kind: 'circle',
      circle: { center: { lat: 40.05, lon: -73.95 }, radius_m: 400 },
    })
  })

  it('uses the polygon when there is no circle and at least three vertices', () => {
    const verts = [
      { lat: 40, lon: -74 },
      { lat: 40.1, lon: -74 },
      { lat: 40.1, lon: -73.9 },
    ]
    expect(resolvePlayBoundary({ boundary: verts })).toEqual({
      kind: 'polygon',
      vertices: verts,
    })
  })

  it('returns null for empty or incomplete arenas', () => {
    expect(resolvePlayBoundary(null)).toBeNull()
    expect(resolvePlayBoundary({})).toBeNull()
    expect(
      resolvePlayBoundary({
        boundary: [
          { lat: 40, lon: -74 },
          { lat: 40.1, lon: -74 },
        ],
      }),
    ).toBeNull()
    expect(
      resolvePlayBoundary({
        boundary_circle: { center: { lat: 40, lon: -74 }, radius_m: 0 },
      }),
    ).toBeNull()
  })
})

describe('arenaIdentityKey and centroid', () => {
  it('builds a stable key and averages polygon vertices', () => {
    const circle = resolvePlayBoundary({
      boundary_circle: { center: { lat: 1, lon: 2 }, radius_m: 50 },
    })
    expect(arenaIdentityKey(circle)).toBe('circle:1,2,50')

    const verts = [
      { lat: 0, lon: 0 },
      { lat: 0, lon: 2 },
      { lat: 2, lon: 2 },
      { lat: 2, lon: 0 },
    ]
    const poly = resolvePlayBoundary({ boundary: verts })
    expect(arenaIdentityKey(poly)).toBe('polygon:0,0|0,2|2,2|2,0')
    expect(centroid(verts)).toEqual({ lat: 1, lon: 1 })
  })
})
