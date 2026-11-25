/**
 * Wall-clock freshness thresholds shared by fix bars and live map pins.
 * Stale means older than `STALE_AFTER_INTERVALS` ping intervals — the same rule as 2 fix bars.
 * Mirror: ios/Manhunt/Domain/PinStaleness.swift. Keep the two in lockstep.
 */

export const STALE_AFTER_INTERVALS = 2

export const DEFAULT_PING_INTERVAL_S = 60

export type FixBars = 0 | 1 | 2 | 3 | 4

export function effectiveIntervalS(pingIntervalS: number): number {
  const value = pingIntervalS > 0 ? pingIntervalS : DEFAULT_PING_INTERVAL_S
  return value
}

/** Bar count for a fix age. Matches `fixFreshness` except when there is no fix (0 bars). */
export function barsForAge(ageS: number, intervalS: number, signalLost: boolean): FixBars {
  if (signalLost) {
    return 1
  }
  if (ageS <= intervalS) {
    return 4
  }
  if (ageS <= intervalS * STALE_AFTER_INTERVALS) {
    return 3
  }
  return 2
}

/** Map pin translucency paired with fix bars so a dim pin matches the leaderboard meter. */
export function pinOpacityForBars(bars: FixBars): number {
  switch (bars) {
    case 4:
      return 1
    case 3:
      return 0.88
    case 2:
      return 0.5
    case 1:
      return 0.45
    default:
      return 0.4
  }
}

export function pinOpacity(input: {
  fixAtMs: number | null
  fixKind?: string | null
  status: string
  pingIntervalS: number
  nowMs: number
}): number {
  if (input.fixAtMs == null || Number.isNaN(input.fixAtMs)) {
    return pinOpacityForBars(0)
  }
  const ageS = Math.max(0, (input.nowMs - input.fixAtMs) / 1000)
  const lost = input.status === 'signal_lost' || input.fixKind === 'last_known'
  const bars = barsForAge(ageS, effectiveIntervalS(input.pingIntervalS), lost)
  return pinOpacityForBars(bars)
}