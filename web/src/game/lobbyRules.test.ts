import { describe, expect, it } from 'vitest'
import { draftFromTimers, overridesFromDraft, ruleErrors } from './lobbyRules'

const current = { headStartS: 60, timeLimitMin: 30, revealIntervalS: 60 as number | null }

describe('lobbyRules', () => {
  it('reads the draft from the view timers, converting the time limit to minutes', () => {
    expect(
      draftFromTimers({ head_start_s: 90, time_limit_s: 45 * 60, reveal_interval_s: 120 }),
    ).toEqual({ headStartS: 90, timeLimitMin: 45, revealIntervalS: 120 })
    expect(draftFromTimers(undefined)).toEqual({
      headStartS: 60,
      timeLimitMin: 30,
      revealIntervalS: null,
    })
  })

  it('sends only the changed fields', () => {
    expect(overridesFromDraft({ ...current, headStartS: 90 }, current)).toEqual({
      head_start: { duration: 90 },
    })
    expect(
      overridesFromDraft({ headStartS: 60, timeLimitMin: 20, revealIntervalS: 30 }, current),
    ).toEqual({ win: { time_limit: 20 }, reveal_fuzzy: { interval: 30 } })
    expect(overridesFromDraft(current, current)).toBeNull()
  })

  it('never sends a reveal interval when reveals are off', () => {
    const off = { ...current, revealIntervalS: null }
    expect(overridesFromDraft({ ...off, headStartS: 61 }, off)).toEqual({
      head_start: { duration: 61 },
    })
  })

  it('accepts the boundaries and rejects values just outside them', () => {
    expect(ruleErrors({ headStartS: 15, timeLimitMin: 5, revealIntervalS: 20 })).toEqual([])
    expect(ruleErrors({ headStartS: 600, timeLimitMin: 180, revealIntervalS: 600 })).toEqual([])
    expect(ruleErrors({ headStartS: 14, timeLimitMin: 30, revealIntervalS: 60 })).toHaveLength(1)
    expect(ruleErrors({ headStartS: 601, timeLimitMin: 181, revealIntervalS: 19 })).toHaveLength(3)
  })

  it('does not block an unrelated edit when head start is off (0 s) and unchanged', () => {
    const off = { headStartS: 0, timeLimitMin: 30, revealIntervalS: 60 as number | null }
    expect(ruleErrors({ ...off, timeLimitMin: 20 }, off)).toEqual([])
    expect(ruleErrors({ ...off, headStartS: 5 }, off)).toHaveLength(1)
  })

  it('rejects NaN and fractions', () => {
    expect(ruleErrors({ headStartS: Number.NaN, timeLimitMin: 30, revealIntervalS: 60 })).toHaveLength(1)
    expect(ruleErrors({ headStartS: 60.5, timeLimitMin: 30, revealIntervalS: 60 })).toHaveLength(1)
  })
})
