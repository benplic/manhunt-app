import { describe, expect, it } from 'vitest'
import { rulesSummaryLine } from './rulesSummary'

describe('rulesSummaryLine', () => {
  it('formats classic timers', () => {
    expect(
      rulesSummaryLine({
        time_limit_s: 1800,
        head_start_s: 60,
        reveal_interval_s: 60,
      }),
    ).toBe('30 min · 1:00 head start · 1:00 pings')
  })

  it('mentions zone shrink when configured', () => {
    expect(
      rulesSummaryLine({
        time_limit_s: 1800,
        head_start_s: 0,
        reveal_interval_s: 90,
        zone: { radius_m: 400, next_radius_m: 300, shrinks_in_s: 120, interval_s: 120 },
      }),
    ).toContain('Zone shrinks')
  })
})