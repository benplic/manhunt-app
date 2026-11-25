import { describe, expect, it } from 'vitest'
import {
  DEFAULT_PING_INTERVAL_S,
  describeAge,
  fixFreshness,
  pingIntervalFromTimers,
  viewerExpectsFix,
} from './fixFreshness'

const NOW = Date.parse('2026-11-24T20:00:00Z')
const at = (secondsAgo: number) => new Date(NOW - secondsAgo * 1000).toISOString()

const base = {
  status: 'active',
  expectsFix: true,
  pingIntervalS: 60,
  nowMs: NOW,
}

describe('fixFreshness', () => {
  it('gives 4 bars up to and including exactly one interval', () => {
    expect(fixFreshness({ ...base, location: { at: at(0) } })?.bars).toBe(4)
    expect(fixFreshness({ ...base, location: { at: at(60) } })?.bars).toBe(4)
  })

  it('gives 3 bars just past one interval and at exactly two', () => {
    expect(fixFreshness({ ...base, location: { at: at(61) } })?.bars).toBe(3)
    expect(fixFreshness({ ...base, location: { at: at(120) } })?.bars).toBe(3)
  })

  it('gives 2 bars when older than two intervals (stale)', () => {
    const reading = fixFreshness({ ...base, location: { at: at(121) } })
    expect(reading?.bars).toBe(2)
    expect(reading?.label).toContain('Stale')
  })

  it('gives 1 bar for signal lost or a last-known fix, however recent', () => {
    expect(fixFreshness({ ...base, status: 'signal_lost', location: { at: at(5) } })?.bars).toBe(1)
    expect(fixFreshness({ ...base, location: { at: at(5), kind: 'last_known' } })?.bars).toBe(1)
  })

  it('gives 0 bars when the viewer should see a fix but none exists', () => {
    const reading = fixFreshness({ ...base, location: null })
    expect(reading?.bars).toBe(0)
    expect(reading?.label).toBe('No fix yet')
  })

  it('draws nothing, not zero bars, when the viewer may not see the player', () => {
    expect(fixFreshness({ ...base, expectsFix: false, location: null })).toBeNull()
  })

  it('still draws bars when a fix arrives that the viewer was not expecting (radar, taunt)', () => {
    expect(fixFreshness({ ...base, expectsFix: false, location: { at: at(10) } })?.bars).toBe(4)
  })

  it('labels the age so it reads as freshness, not signal strength', () => {
    expect(fixFreshness({ ...base, location: { at: at(40) } })?.label).toBe(
      'Last fix 40 seconds ago',
    )
    expect(fixFreshness({ ...base, location: { at: at(1) } })?.label).toBe('Last fix 1 second ago')
    expect(fixFreshness({ ...base, location: { at: at(150) } })?.label).toContain('2 minutes')
  })

  it('clamps a fix timestamped in the future (clock skew) to just now', () => {
    const reading = fixFreshness({ ...base, location: { at: at(-30) } })
    expect(reading?.bars).toBe(4)
    expect(reading?.ageS).toBe(0)
  })

  it('treats an unparseable timestamp as no fix instead of throwing', () => {
    expect(fixFreshness({ ...base, location: { at: 'not a date' } })?.bars).toBe(0)
  })

  it('scales with the match ping interval', () => {
    const slow = { ...base, pingIntervalS: 300 }
    expect(fixFreshness({ ...slow, location: { at: at(290) } })?.bars).toBe(4)
    expect(fixFreshness({ ...slow, location: { at: at(601) } })?.bars).toBe(2)
  })
})

describe('pingIntervalFromTimers', () => {
  it('prefers the hider reveal interval, then the seeker one, then the default', () => {
    expect(pingIntervalFromTimers({ reveal_interval_s: 90, seeker_reveal_interval_s: 30 })).toBe(90)
    expect(pingIntervalFromTimers({ reveal_interval_s: null, seeker_reveal_interval_s: 30 })).toBe(
      30,
    )
    expect(pingIntervalFromTimers({ reveal_interval_s: null })).toBe(DEFAULT_PING_INTERVAL_S)
    expect(pingIntervalFromTimers(undefined)).toBe(DEFAULT_PING_INTERVAL_S)
  })
})

describe('describeAge', () => {
  it('uses seconds, minutes, then hours', () => {
    expect(describeAge(0)).toBe('0 seconds')
    expect(describeAge(59.9)).toBe('59 seconds')
    expect(describeAge(60)).toBe('1 minute')
    expect(describeAge(3600)).toBe('1 hour')
  })
})

describe('viewerExpectsFix', () => {
  const args = {
    viewerId: 'me',
    viewerRole: 'hider',
    viewerStatus: 'active',
    playerId: 'them',
    playerRole: 'hider',
    phase: 'active',
  }

  it('expects teammates and yourself, not the other team', () => {
    expect(viewerExpectsFix(args)).toBe(true)
    expect(viewerExpectsFix({ ...args, playerId: 'me', playerRole: 'seeker' })).toBe(true)
    expect(viewerExpectsFix({ ...args, playerRole: 'seeker' })).toBe(false)
  })

  it('expects nothing in the lobby or from unassigned players', () => {
    expect(viewerExpectsFix({ ...args, phase: 'lobby' })).toBe(false)
    expect(viewerExpectsFix({ ...args, viewerRole: 'unassigned', playerRole: 'unassigned' })).toBe(
      false,
    )
  })

  it('expects only your own fix when you are out', () => {
    expect(viewerExpectsFix({ ...args, viewerStatus: 'eliminated' })).toBe(false)
    expect(viewerExpectsFix({ ...args, viewerStatus: 'eliminated', playerId: 'me' })).toBe(true)
  })
})
