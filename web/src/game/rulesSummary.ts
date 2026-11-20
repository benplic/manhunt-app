import type { ViewTimers } from '../api/types'

function clock(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

/** Read-only rules line for the lobby (matches iOS RulesSummary). */
export function rulesSummaryLine(timers: ViewTimers | undefined): string | null {
  if (!timers) {
    return null
  }
  const timeLimit = timers.time_limit_s ?? 30 * 60
  const headStart = timers.head_start_s ?? 0
  const parts: string[] = [`${Math.max(1, Math.floor(timeLimit / 60))} min`]
  parts.push(headStart > 0 ? `${clock(headStart)} head start` : 'No head start')
  if (timers.reveal_interval_s != null) {
    parts.push(`${clock(timers.reveal_interval_s)} pings`)
  } else {
    parts.push('No pings')
  }
  if (timers.zone != null) {
    parts.push('Zone shrinks')
  }
  return parts.join(' · ')
}