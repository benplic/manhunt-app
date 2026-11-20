import type { ArenaZone, ArenaZoneKind } from '../api/types'

export type VisibleZonesInput = {
  arenaZones: ArenaZone[]
  spawnLockZones: ArenaZone[]
  phase: string
  emphasizeSpawn: boolean
}

export type ZoneDrawStyle = {
  color: string
  fillColor: string
  fillOpacity: number
  strokeOpacity: number
  weight: number
}

const TINT: Record<ArenaZoneKind, string> = {
  safe: '#3d9a6a',
  out_of_bounds: '#e0a040',
  seeker_spawn: '#4a7fd4',
}

/**
 * Filter + order zones for the live map (mirrors iOS LiveMapZones).
 * Seeker spawn stays visible only during head start or spawn-lock emphasis.
 * Out-of-bounds paints last so holes read clearly.
 */
export function visibleZones(input: VisibleZonesInput): ArenaZone[] {
  const showSpawn = input.phase === 'head_start' || input.emphasizeSpawn
  const base = input.arenaZones.filter(
    (zone) => zone.kind !== 'seeker_spawn' || showSpawn,
  )
  let merged = base
  if (showSpawn) {
    const extras = input.spawnLockZones.filter((spawn) => {
      return !base.some(
        (existing) =>
          existing.id === spawn.id ||
          (existing.kind === spawn.kind && shapesEqual(existing, spawn)),
      )
    })
    merged = [...base, ...extras]
  }
  const nonOut = merged.filter((z) => z.kind !== 'out_of_bounds')
  const outs = merged.filter((z) => z.kind === 'out_of_bounds')
  return [...nonOut, ...outs]
}

function shapesEqual(a: ArenaZone, b: ArenaZone): boolean {
  return JSON.stringify(a.shape) === JSON.stringify(b.shape)
}

export function zoneStyle(
  kind: ArenaZoneKind,
  options: { emphasizeSpawn: boolean; lockdown: boolean },
): ZoneDrawStyle {
  const tint = TINT[kind]
  const emphasize = options.emphasizeSpawn && kind === 'seeker_spawn'
  const fillBase = emphasize ? 0.45 : 0.28
  let fillOpacity = fillBase
  let strokeOpacity = 1
  if (kind === 'safe' && options.lockdown) {
    fillOpacity = fillBase * (1 - 0.78)
    strokeOpacity = Math.max(0.25, 1 - 0.65)
  }
  return {
    color: tint,
    fillColor: tint,
    fillOpacity,
    strokeOpacity,
    weight: emphasize ? 4 : 2,
  }
}

/** True when the seeker spawn lock chrome should emphasize spawn polygons. */
export function emphasizeSpawnFromView(input: {
  phase: string
  seeker_lock?: string | null
}): boolean {
  return input.seeker_lock === 'spawn_zone' && input.phase === 'head_start'
}
