import { describe, expect, it } from 'vitest'
import {
  AVATAR_PALETTE,
  AVATAR_TEXT,
  TEAM_COLORS,
  assignAvatarStyles,
  colorDistance,
  contrastRatio,
  idHash,
  initialsFor,
} from './avatarStyle'

function uuid(n: number): string {
  return `00000000-0000-4000-8000-${n.toString(16).padStart(12, '0')}`
}

describe('initialsFor', () => {
  it('uses the first letter of the first two words', () => {
    expect(initialsFor('Ryan O\u2019Donnell')).toBe('RO')
    expect(initialsFor('  casey   lee  kim ')).toBe('CL')
  })

  it('handles empty, one-letter, accented, and emoji names', () => {
    expect(initialsFor('')).toBe('?')
    expect(initialsFor('   ')).toBe('?')
    expect(initialsFor('x')).toBe('X')
    expect(initialsFor('\u00e9lodie')).toBe('\u00c9')
    expect(initialsFor('Zo\u00eb \u{1F98A}')).toBe('Z\u{1F98A}')
  })
})

describe('idHash', () => {
  it('matches the cross-platform fixture values', () => {
    // The same fixtures live in ios/ManhuntTests/RosterLobbyAvatarTests.swift.
    expect(idHash('')).toBe(5381)
    expect(idHash('a')).toBe(177670)
    expect(idHash(uuid(1))).toBe(919571334)
    expect(idHash(uuid(4))).toBe(919571337)
  })

  it('assigns the cross-platform fixture roster the same slots and cues', () => {
    const styles = assignAvatarStyles([
      { id: uuid(1), name: 'Sam Smith' },
      { id: uuid(2), name: 'Sara Stone' },
      { id: uuid(3), name: 'Sid Shaw' },
      { id: uuid(4), name: 'Zed Zimmer' },
    ])
    expect([1, 2, 3, 4].map((n) => [styles.get(uuid(n))?.colorIndex, styles.get(uuid(n))?.cue])).toEqual([
      [6, 0],
      [7, 1],
      [8, 2],
      [9, 0],
    ])
  })
})

describe('assignAvatarStyles', () => {
  it('never gives two same-initial players the same color while colors remain', () => {
    const players = Array.from({ length: AVATAR_PALETTE.length }, (_, i) => ({
      id: uuid(i + 1),
      name: `Sam Smith ${i}`,
    }))
    const styles = assignAvatarStyles(players)
    const colors = new Set(players.map((p) => styles.get(p.id)?.colorIndex))
    expect(colors.size).toBe(players.length)
  })

  it('gives each same-initial player a different ring cue and none to a unique initial', () => {
    const players = [
      { id: uuid(1), name: 'Sam Smith' },
      { id: uuid(2), name: 'Sara Stone' },
      { id: uuid(3), name: 'Sid Shaw' },
      { id: uuid(4), name: 'Zed Zimmer' },
    ]
    const styles = assignAvatarStyles(players)
    expect(styles.get(uuid(1))?.cue).toBe(0)
    expect(styles.get(uuid(2))?.cue).toBe(1)
    expect(styles.get(uuid(3))?.cue).toBe(2)
    expect(styles.get(uuid(4))?.cue).toBe(0)
  })

  it('is independent of the order the roster arrives in', () => {
    const players = Array.from({ length: 12 }, (_, i) => ({ id: uuid(i + 1), name: 'Pat Poe' }))
    const forward = assignAvatarStyles(players)
    const backward = assignAvatarStyles([...players].reverse())
    for (const player of players) {
      expect(backward.get(player.id)).toEqual(forward.get(player.id))
    }
  })

  it('treats ids case-insensitively', () => {
    const upper = assignAvatarStyles([{ id: uuid(10).toUpperCase(), name: 'Al Bo' }])
    const lower = assignAvatarStyles([{ id: uuid(10), name: 'Al Bo' }])
    expect([...upper.values()][0].colorIndex).toBe([...lower.values()][0].colorIndex)
  })

  it('keeps every player in a 27 player roster with many repeated initials', () => {
    const names = ['Alex Adams', 'Alice Allen', 'Ben Brown', 'Bella Bell', 'Cal Cruz']
    const players = Array.from({ length: 27 }, (_, i) => ({
      id: uuid(i + 1),
      name: names[i % names.length],
    }))
    const styles = assignAvatarStyles(players)
    expect(styles.size).toBe(27)
    for (const initials of ['AA', 'BB', 'CC']) {
      const group = players.filter((p) => initialsFor(p.name) === initials)
      const used = new Set(group.map((p) => styles.get(p.id)?.colorIndex))
      expect(used.size).toBe(Math.min(group.length, AVATAR_PALETTE.length))
    }
  })

  it('falls back to a duplicate color only when same-initial players outnumber colors', () => {
    const players = Array.from({ length: AVATAR_PALETTE.length + 3 }, (_, i) => ({
      id: uuid(i + 1),
      name: 'Kim Kane',
    }))
    const styles = assignAvatarStyles(players)
    const used = new Set([...styles.values()].map((s) => s.colorIndex))
    expect(used.size).toBe(AVATAR_PALETTE.length)
    const cues = new Set([...styles.values()].map((s) => s.cue))
    expect(cues.size).toBe(4)
    // The 13th same-initial player still advances the ring cue instead of repeating the last.
    expect(styles.get(uuid(13))?.cue).toBe(0)
    expect(styles.get(uuid(14))?.cue).toBe(1)
  })

  it('keeps a player on the same color when an unrelated player joins', () => {
    const before = assignAvatarStyles([{ id: uuid(5), name: 'Dee Dunn' }])
    const after = assignAvatarStyles([
      { id: uuid(5), name: 'Dee Dunn' },
      { id: uuid(9), name: 'Eli Evans' },
    ])
    expect(after.get(uuid(5))?.colorIndex).toBe(before.get(uuid(5))?.colorIndex)
  })
})

describe('palette', () => {
  it('has readable dark text on every fill (WCAG AA for small text)', () => {
    for (const color of AVATAR_PALETTE) {
      expect(contrastRatio(color, AVATAR_TEXT)).toBeGreaterThanOrEqual(4.5)
    }
  })

  it('has no near-duplicate colors', () => {
    for (let i = 0; i < AVATAR_PALETTE.length; i += 1) {
      for (let j = i + 1; j < AVATAR_PALETTE.length; j += 1) {
        expect(colorDistance(AVATAR_PALETTE[i], AVATAR_PALETTE[j])).toBeGreaterThanOrEqual(40)
      }
    }
  })

  it('stays visibly different from the team colors', () => {
    for (const color of AVATAR_PALETTE) {
      for (const team of Object.values(TEAM_COLORS)) {
        expect(colorDistance(color, team)).toBeGreaterThanOrEqual(60)
      }
    }
  })
})
