import type { ViewTimers } from '../api/types'

/**
 * Host-editable rules in the lobby. Limits mirror RANGES in server/app/presets/classic.py,
 * which is the authority; the server rejects anything outside them with VALIDATION_FAILED.
 */
export const RULE_LIMITS = {
  headStartS: { min: 15, max: 600 },
  timeLimitMin: { min: 5, max: 180 },
  revealIntervalS: { min: 20, max: 600 },
} as const

export type RuleDraft = {
  headStartS: number
  timeLimitMin: number
  /** Null when hider reveals are off in this match, so there is no interval to edit. */
  revealIntervalS: number | null
}

export type RuleOverrides = Record<string, Record<string, number>>

export function draftFromTimers(timers: ViewTimers | undefined): RuleDraft {
  return {
    headStartS: timers?.head_start_s ?? 60,
    timeLimitMin: Math.round((timers?.time_limit_s ?? 30 * 60) / 60),
    revealIntervalS: timers?.reveal_interval_s ?? null,
  }
}

function rangeError(label: string, value: number, min: number, max: number): string | null {
  if (!Number.isFinite(value) || !Number.isInteger(value)) {
    return `${label} must be a whole number.`
  }
  if (value < min || value > max) {
    return `${label} must be between ${min} and ${max}.`
  }
  return null
}

/**
 * With current, only changed fields are checked. A match with head start off reports 0 seconds, which is
 * outside the editable range, and that must not block an unrelated edit.
 */
export function ruleErrors(draft: RuleDraft, current?: RuleDraft): string[] {
  const errors = [
    (current && draft.headStartS === current.headStartS)
      ? null
      : rangeError(
          'Head start',
          draft.headStartS,
          RULE_LIMITS.headStartS.min,
          RULE_LIMITS.headStartS.max,
        ),
    (current && draft.timeLimitMin === current.timeLimitMin)
      ? null
      : rangeError(
          'Time limit',
          draft.timeLimitMin,
          RULE_LIMITS.timeLimitMin.min,
          RULE_LIMITS.timeLimitMin.max,
        ),
    draft.revealIntervalS === null || (current && draft.revealIntervalS === current.revealIntervalS)
      ? null
      : rangeError(
          'Reveal interval',
          draft.revealIntervalS,
          RULE_LIMITS.revealIntervalS.min,
          RULE_LIMITS.revealIntervalS.max,
        ),
  ]
  return errors.filter((message): message is string => message !== null)
}

/** Only the fields that changed, shaped for POST /v1/games/{id}/rules. Null when nothing changed. */
export function overridesFromDraft(draft: RuleDraft, current: RuleDraft): RuleOverrides | null {
  const overrides: RuleOverrides = {}
  if (draft.headStartS !== current.headStartS) {
    overrides.head_start = { duration: draft.headStartS }
  }
  if (draft.timeLimitMin !== current.timeLimitMin) {
    overrides.win = { time_limit: draft.timeLimitMin }
  }
  if (draft.revealIntervalS !== null && draft.revealIntervalS !== current.revealIntervalS) {
    overrides.reveal_fuzzy = { interval: draft.revealIntervalS }
  }
  return Object.keys(overrides).length > 0 ? overrides : null
}
