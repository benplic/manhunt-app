import { describe, expect, it } from 'vitest'
import { groupRoster, rankPlayers, statusNote, type RosterPlayer } from './roster'

function player(id: string, role: string, points: number, extra: Partial<RosterPlayer> = {}) {
  return { player_id: id, display_name: id, role, status: 'active', points, ...extra }
}

describe('groupRoster', () => {
  it('returns Seekers and Hiders sections with overall rank and points preserved', () => {
    const sections = groupRoster([
      player('a', 'hider', 50),
      player('b', 'seeker', 80),
      player('c', 'hider', 20),
      player('d', 'seeker', 10),
    ])
    expect(sections.map((s) => s.title)).toEqual(['Seekers', 'Hiders'])
    expect(sections[0].rows.map((r) => [r.player.player_id, r.rank, r.points])).toEqual([
      ['b', 1, 80],
      ['d', 4, 10],
    ])
    expect(sections[1].rows.map((r) => [r.player.player_id, r.rank, r.points])).toEqual([
      ['a', 2, 50],
      ['c', 3, 20],
    ])
  })

  it('files converted players under Seekers with a tagged marker', () => {
    const sections = groupRoster([
      player('a', 'hider', 5),
      player('b', 'seeker', 5, { converted_from_hider: true }),
    ])
    const seekers = sections.find((s) => s.id === 'seekers')
    expect(seekers?.rows[0].tagged).toBe(true)
    expect(sections.find((s) => s.id === 'hiders')?.rows[0].tagged).toBe(false)
  })

  it('keeps eliminated hiders in Hiders, not Seekers', () => {
    const sections = groupRoster([
      player('a', 'hider', 5, { status: 'eliminated' }),
      player('b', 'seeker', 5),
    ])
    expect(sections.find((s) => s.id === 'hiders')?.rows).toHaveLength(1)
  })

  it('puts lobby players with no role in their own section and drops empty ones', () => {
    const lobby = groupRoster([player('a', 'unassigned', 0), player('b', 'unassigned', 0)])
    expect(lobby.map((s) => s.id)).toEqual(['unassigned'])
    expect(groupRoster([])).toEqual([])
  })

  it('prefers points_earned over points', () => {
    const [section] = groupRoster([player('a', 'hider', 5, { points_earned: 40 })])
    expect(section.rows[0].points).toBe(40)
  })
})

describe('rankPlayers', () => {
  it('ties share a rank and the next rank skips', () => {
    const rows = rankPlayers([
      player('a', 'hider', 10),
      player('b', 'hider', 10),
      player('c', 'hider', 5),
    ])
    expect(rows.map((r) => r.rank)).toEqual([1, 1, 3])
  })

  it('handles a 27 player roster without losing anyone', () => {
    const players = Array.from({ length: 27 }, (_, i) =>
      player(`p${String(i).padStart(2, '0')}`, i % 3 === 0 ? 'seeker' : 'hider', i % 5),
    )
    const sections = groupRoster(players)
    expect(sections.reduce((n, s) => n + s.rows.length, 0)).toBe(27)
  })
})

describe('statusNote', () => {
  it('names out and dark players', () => {
    expect(statusNote('eliminated')).toBe('out')
    expect(statusNote('signal_lost')).toBe('dark')
    expect(statusNote('active')).toBe('')
  })
})
