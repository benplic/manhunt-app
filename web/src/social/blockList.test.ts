import { afterEach, describe, expect, it } from 'vitest'
import {
  anonymizedName,
  blockPlayer,
  displayNameFor,
  isBlocked,
  listBlockedPlayers,
  reportMailto,
  unblockPlayer,
} from './blockList'

afterEach(() => {
  localStorage.clear()
})

describe('blockList', () => {
  it('blocks, anonymizes, and unblocks on this device', () => {
    blockPlayer('b-id', 'Ben')
    blockPlayer('a-id', 'Ada')
    expect(isBlocked('a-id')).toBe(true)
    expect(listBlockedPlayers()).toHaveLength(2)
    // Sorted by id: a-id is #1, b-id is #2.
    expect(anonymizedName('a-id')).toBe('Blocked Player #1')
    expect(displayNameFor('b-id', 'Ben')).toBe('Blocked Player #2')
    unblockPlayer('a-id')
    expect(isBlocked('a-id')).toBe(false)
    expect(displayNameFor('b-id', 'Ben')).toBe('Blocked Player #1')
  })

  it('builds a report mailto without leaking coords', () => {
    const href = reportMailto({
      gameId: 'g1',
      playerId: 'p1',
      displayName: 'Ada',
      supportEmail: 'support@example.com',
    })
    expect(href.startsWith('mailto:support@example.com?')).toBe(true)
    expect(href).toContain('game_id')
    expect(href).toContain('player_id')
    expect(href).not.toContain('lat')
  })
})
