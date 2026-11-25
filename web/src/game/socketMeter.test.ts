import { describe, expect, it } from 'vitest'
import {
  SOCKET_DOWN_AFTER_FAILURES,
  SOCKET_STALE_MS,
  meterAriaLabel,
  meterExplanation,
  socketMeter,
} from './socketMeter'

const base = { connected: false, failureStreak: 0, lastMessageAgeMs: null as number | null }

describe('socketMeter', () => {
  it('shows 4 bars when connected and the last message is within the window', () => {
    expect(socketMeter({ ...base, connected: true, lastMessageAgeMs: 0 }).bars).toBe(4)
    expect(socketMeter({ ...base, connected: true, lastMessageAgeMs: SOCKET_STALE_MS }).bars).toBe(
      4,
    )
  })

  it('shows 3 bars when connected but the last message is older than the window', () => {
    const reading = socketMeter({
      ...base,
      connected: true,
      lastMessageAgeMs: SOCKET_STALE_MS + 1,
    })
    expect(reading).toEqual({ bars: 3, label: 'slow' })
  })

  it('treats a connected socket with no message yet as quiet', () => {
    expect(socketMeter({ ...base, connected: true, lastMessageAgeMs: null }).bars).toBe(3)
  })

  it('shows 2 bars on the first retry and while the first connect is in progress', () => {
    expect(socketMeter({ ...base, failureStreak: 0 }).bars).toBe(2)
    expect(socketMeter({ ...base, failureStreak: 1 })).toEqual({
      bars: 2,
      label: 'reconnecting',
    })
  })

  it('shows 1 bar for repeated failures', () => {
    expect(socketMeter({ ...base, failureStreak: 2 })).toEqual({ bars: 1, label: 'unstable' })
    expect(socketMeter({ ...base, failureStreak: SOCKET_DOWN_AFTER_FAILURES - 1 }).bars).toBe(1)
  })

  it('shows 0 bars when down', () => {
    expect(socketMeter({ ...base, failureStreak: SOCKET_DOWN_AFTER_FAILURES })).toEqual({
      bars: 0,
      label: 'down',
    })
  })

  it('shows 0 bars while the device is offline, even on the first failure', () => {
    expect(socketMeter({ ...base, failureStreak: 1, offline: true }).bars).toBe(0)
  })

  it('ignores offline when the socket is actually connected', () => {
    expect(socketMeter({ ...base, connected: true, lastMessageAgeMs: 100, offline: true }).bars).toBe(
      4,
    )
  })

  it('names the state in words so color is never the only signal', () => {
    expect(meterAriaLabel({ bars: 4, label: 'good' })).toBe('Connection: good')
    expect(meterAriaLabel({ bars: 0, label: 'down' })).toBe('Connection: down')
  })

  it('explains the state with the age of the last message', () => {
    expect(meterExplanation({ bars: 4, label: 'good' }, 2400)).toBe(
      'Connected. Updates are arriving. Last update 2s ago.',
    )
    expect(meterExplanation({ bars: 2, label: 'reconnecting' }, null)).toBe(
      'Reconnecting to the hunt server. No update yet.',
    )
    expect(meterExplanation({ bars: 3, label: 'slow' }, -50)).toContain('0s ago')
  })
})
