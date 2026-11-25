/**
 * Four-bar meter for YOUR socket to the hunt server. It is not GPS quality and it says
 * nothing about other players.
 *
 * Mapping (the 5 s window is decided by the user; keep iOS `SocketMeter.swift` identical):
 *   4 bars  connected, last server message within SOCKET_STALE_MS
 *   3 bars  connected, last server message older than SOCKET_STALE_MS
 *   2 bars  not connected, first retry (or the first connect still in progress)
 *   1 bar   not connected, repeated failures
 *   0 bars  down: the browser is offline, or failures kept piling up
 */

export const SOCKET_STALE_MS = 5_000
/** From this many failed attempts in a row the socket counts as down. TODO: tune with playtest data. */
export const SOCKET_DOWN_AFTER_FAILURES = 5

export type MeterInput = {
  connected: boolean
  failureStreak: number
  /** Milliseconds since the last server message; null when none has arrived yet. */
  lastMessageAgeMs: number | null
  /** The browser or phone reports no network at all. */
  offline?: boolean
}

export type MeterLevel = 0 | 1 | 2 | 3 | 4
export type MeterLabel = 'good' | 'slow' | 'reconnecting' | 'unstable' | 'down'

export type MeterReading = {
  bars: MeterLevel
  label: MeterLabel
}

export function socketMeter(input: MeterInput): MeterReading {
  if (input.connected) {
    // A connected socket that has not heard anything yet is as quiet as it gets.
    const quiet = input.lastMessageAgeMs === null || input.lastMessageAgeMs > SOCKET_STALE_MS
    return quiet ? { bars: 3, label: 'slow' } : { bars: 4, label: 'good' }
  }
  if (input.offline || input.failureStreak >= SOCKET_DOWN_AFTER_FAILURES) {
    return { bars: 0, label: 'down' }
  }
  if (input.failureStreak >= 2) {
    return { bars: 1, label: 'unstable' }
  }
  return { bars: 2, label: 'reconnecting' }
}

const SUMMARY: Record<MeterLabel, string> = {
  good: 'Connected. Updates are arriving.',
  slow: 'Connected, but the last update was a while ago.',
  reconnecting: 'Reconnecting to the hunt server.',
  unstable: 'Your connection keeps dropping. Updates may be late.',
  down: 'No connection to the hunt server.',
}

/** Short sentence for the tap explanation, with the age of the last update when known. */
export function meterExplanation(reading: MeterReading, lastMessageAgeMs: number | null): string {
  const base = SUMMARY[reading.label]
  if (lastMessageAgeMs === null) {
    return `${base} No update yet.`
  }
  const seconds = Math.max(0, Math.round(lastMessageAgeMs / 1000))
  return `${base} Last update ${seconds}s ago.`
}

/** Accessible name. The word carries the meaning; the bars are decoration. */
export function meterAriaLabel(reading: MeterReading): string {
  return `Connection: ${reading.label}`
}
