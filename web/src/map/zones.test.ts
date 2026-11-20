import { describe, expect, it } from 'vitest'
import type { ArenaZone } from '../api/types'
import { visibleZones, zoneStyle } from './zones'

const safe: ArenaZone = {
  id: 'safe-1',
  name: 'Picnic',
  kind: 'safe',
  shape: { type: 'circle', center: { lat: 40, lon: -74 }, radius_m: 20 },
}

const spawn: ArenaZone = {
  id: 'spawn-1',
  name: 'Gate',
  kind: 'seeker_spawn',
  shape: {
    type: 'polygon',
    vertices: [
      { lat: 40.01, lon: -74.01 },
      { lat: 40.02, lon: -74.01 },
      { lat: 40.02, lon: -74.0 },
    ],
  },
}

const oob: ArenaZone = {
  id: 'oob-1',
  name: 'Pond',
  kind: 'out_of_bounds',
  shape: {
    type: 'polygon',
    vertices: [
      { lat: 40.03, lon: -74.02 },
      { lat: 40.04, lon: -74.02 },
      { lat: 40.04, lon: -74.01 },
    ],
  },
}

describe('visibleZones', () => {
  it('hides seeker spawn after head start unless emphasized', () => {
    const during = visibleZones({
      arenaZones: [safe, spawn, oob],
      spawnLockZones: [],
      phase: 'head_start',
      emphasizeSpawn: false,
    })
    expect(during.map((z) => z.id)).toEqual(['safe-1', 'spawn-1', 'oob-1'])

    const after = visibleZones({
      arenaZones: [safe, spawn, oob],
      spawnLockZones: [],
      phase: 'active',
      emphasizeSpawn: false,
    })
    expect(after.map((z) => z.id)).toEqual(['safe-1', 'oob-1'])
  })

  it('merges spawn_lock zones during head start and keeps out_of_bounds last', () => {
    const extraSpawn: ArenaZone = {
      ...spawn,
      id: 'spawn-lock',
      name: 'Lock spawn',
    }
    const list = visibleZones({
      arenaZones: [oob, safe],
      spawnLockZones: [extraSpawn],
      phase: 'head_start',
      emphasizeSpawn: true,
    })
    expect(list.map((z) => z.kind)).toEqual(['safe', 'seeker_spawn', 'out_of_bounds'])
    expect(list.map((z) => z.id)).toEqual(['safe-1', 'spawn-lock', 'oob-1'])
  })
})

describe('zoneStyle', () => {
  it('dims safe zones under lockdown and thickens emphasized spawn', () => {
    const normalSafe = zoneStyle('safe', { emphasizeSpawn: false, lockdown: false })
    const dimSafe = zoneStyle('safe', { emphasizeSpawn: false, lockdown: true })
    expect(dimSafe.fillOpacity).toBeLessThan(normalSafe.fillOpacity)
    expect(dimSafe.strokeOpacity).toBeLessThan(normalSafe.strokeOpacity)

    const spawnQuiet = zoneStyle('seeker_spawn', { emphasizeSpawn: false, lockdown: false })
    const spawnHot = zoneStyle('seeker_spawn', { emphasizeSpawn: true, lockdown: false })
    expect(spawnHot.weight).toBeGreaterThan(spawnQuiet.weight)
    expect(spawnHot.fillOpacity).toBeGreaterThan(spawnQuiet.fillOpacity)
  })
})
