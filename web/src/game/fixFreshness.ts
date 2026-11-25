/**
 * How fresh a player's last location fix is, as 0-4 bars.
 *
 * This is FRESHNESS, not radio signal: the server never sees RSSI, only when the last fix
 * was recorded. Keep the word "fix" in every label so nobody reads it as signal strength.
 * Thresholds are shared with stale map pins: stale means older than 2 ping intervals,
 * measured in wall-clock time from the fix's own `at` timestamp (never game seconds).
 * Mirror: ios/Manhunt/Domain/FixFreshness.swift. Keep the two in lockstep.
 */

export type FixBars = 0 | 1 | 2 | 3 | 4

export type FixReading = {
  bars: FixBars
  /** Short spoken label, for example "Last fix 40 seconds ago". */
  label: string
  /** Wall-clock age of the fix in seconds, or null when there is no fix to age. */
  ageS: number | null
}

export type FixLocation = {
  at: string
  kind?: string
}

/**
 * Used when the match has no ping interval (reveals off).
 * TODO: share one constant with the map-pin staleness plan once that helper lands.
 */
export const DEFAULT_PING_INTERVAL_S = 60

export type FixFreshnessInput = {
  location: FixLocation | null | undefined
  status: string
  /** True when the viewer is allowed to see this player's fix, so a missing one means "no fix". */
  expectsFix: boolean
  pingIntervalS: number
  /** Epoch milliseconds. Injected so tests never wait. */
  nowMs: number
}

export function pingIntervalFromTimers(
  timers:
    | { reveal_interval_s?: number | null; seeker_reveal_interval_s?: number | null }
    | null
    | undefined,
): number {
  const candidates = [timers?.reveal_interval_s, timers?.seeker_reveal_interval_s]
  for (const value of candidates) {
    if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
      return value
    }
  }
  return DEFAULT_PING_INTERVAL_S
}

export function describeAge(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds))
  const plural = (n: number, unit: string) => `${n} ${unit}${n === 1 ? '' : 's'}`
  if (whole < 60) {
    return plural(whole, 'second')
  }
  if (whole < 3600) {
    return plural(Math.floor(whole / 60), 'minute')
  }
  return plural(Math.floor(whole / 3600), 'hour')
}

/**
 * Whether the viewer should be able to see this player's fix at all.
 * The server sends `location: null` both for "hidden from you" and "no fix yet", so the
 * client decides which one a null means. Hidden players render nothing, never zero bars.
 */
export function viewerExpectsFix(args: {
  viewerId: string
  viewerRole: string
  viewerStatus: string
  playerId: string
  playerRole: string
  phase: string
}): boolean {
  if (args.phase === 'lobby') {
    return false
  }
  if (args.playerId === args.viewerId) {
    return true
  }
  // TODO: the map-pin plan stops showing teammates to out players. Until it lands this
  // mirrors the server today; an eliminated viewer only expects their own fix.
  if (args.viewerStatus === 'eliminated') {
    return false
  }
  return args.playerRole !== 'unassigned' && args.playerRole === args.viewerRole
}

/** Returns null when nothing should be drawn (the viewer may not see this player's fix). */
export function fixFreshness(input: FixFreshnessInput): FixReading | null {
  const { location, status, expectsFix, pingIntervalS, nowMs } = input
  if (!location) {
    if (!expectsFix) {
      return null
    }
    if (status === 'signal_lost') {
      return { bars: 1, label: 'Signal lost, no fix on record', ageS: null }
    }
    return { bars: 0, label: 'No fix yet', ageS: null }
  }

  const fixMs = Date.parse(location.at)
  if (Number.isNaN(fixMs)) {
    return { bars: 0, label: 'No fix yet', ageS: null }
  }
  // A phone clock a little behind the server would give negative ages. Clamp to "just now".
  const ageS = Math.max(0, (nowMs - fixMs) / 1000)
  const age = describeAge(ageS)

  if (status === 'signal_lost' || location.kind === 'last_known') {
    return { bars: 1, label: `Signal lost, last fix ${age} ago`, ageS }
  }
  const interval = pingIntervalS > 0 ? pingIntervalS : DEFAULT_PING_INTERVAL_S
  const label = `Last fix ${age} ago`
  // Boundaries are inclusive: exactly 1 interval is still 4 bars, exactly 2 is still 3.
  if (ageS <= interval) {
    return { bars: 4, label, ageS }
  }
  if (ageS <= interval * 2) {
    return { bars: 3, label, ageS }
  }
  return { bars: 2, label: `Stale fix, ${age} old`, ageS }
}
