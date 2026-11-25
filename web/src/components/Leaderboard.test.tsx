import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { Leaderboard } from './Leaderboard'

const NOW = Date.parse('2026-11-24T20:00:00Z')
const at = (secondsAgo: number) => new Date(NOW - secondsAgo * 1000).toISOString()

type Row = PlayerView['players'][number]

function row(id: string, name: string, role: string, extra: Partial<Row> = {}): Row {
  return {
    player_id: id,
    display_name: name,
    role,
    status: 'active',
    is_host: false,
    points: 0,
    ...extra,
  }
}

function view(players: Row[], overrides: Partial<PlayerView> = {}): PlayerView {
  return {
    game_id: 'g1',
    join_code: 'ABCDEF',
    phase: 'active',
    you: { player_id: 'me', role: 'hider', status: 'active', is_host: false },
    players,
    timers: { reveal_interval_s: 60 },
    ...overrides,
  }
}

function renderBoard(v: PlayerView) {
  return render(<Leaderboard view={v} onBlock={vi.fn()} onReport={vi.fn()} now={() => NOW} />)
}

describe('Leaderboard', () => {
  it('shows Seekers and Hiders sections with rank and points', () => {
    renderBoard(
      view([
        row('me', 'Casey Lee', 'hider', {
          points: 30,
          location: { lat: 1, lon: 1, accuracy_m: 5, at: at(10), kind: 'exact' },
        }),
        row('s1', 'Sam Smith', 'seeker', { points: 50 }),
        row('h1', 'Hana Hill', 'hider', { points: 10 }),
      ]),
    )
    const seekers = screen.getByRole('region', { name: 'Seekers' })
    const hiders = screen.getByRole('region', { name: 'Hiders' })
    expect(within(seekers).getByText(/Sam Smith/)).toBeInTheDocument()
    expect(within(seekers).getByText(/50 pts/)).toBeInTheDocument()
    expect(within(hiders).getByText(/Casey Lee/)).toBeInTheDocument()
    expect(within(hiders).getByText(/Hana Hill/)).toBeInTheDocument()
    expect(within(hiders).getByText('2.')).toBeInTheDocument()
  })

  it('marks a converted hider as tagged under Seekers', () => {
    renderBoard(
      view([
        row('me', 'Casey', 'hider'),
        row('s2', 'Pat Poe', 'seeker', { converted_from_hider: true }),
      ]),
    )
    const seekers = screen.getByRole('region', { name: 'Seekers' })
    expect(within(seekers).getByText('tagged')).toBeInTheDocument()
  })

  it('labels the freshness bars with the fix age and never calls it signal', () => {
    renderBoard(
      view([
        row('me', 'Casey', 'hider', {
          location: { lat: 1, lon: 1, accuracy_m: 5, at: at(40), kind: 'exact' },
        }),
      ]),
    )
    expect(screen.getByRole('img', { name: 'Last fix 40 seconds ago' })).toBeInTheDocument()
    expect(screen.queryByText(/signal strength/i)).toBeNull()
  })

  it('draws nothing for an opposing player the viewer cannot see, and no fix for a teammate', () => {
    renderBoard(
      view([
        row('me', 'Casey', 'hider'),
        row('h2', 'Hana Hill', 'hider'),
        row('s1', 'Sam Smith', 'seeker'),
      ]),
    )
    const seekers = screen.getByRole('region', { name: 'Seekers' })
    expect(within(seekers).queryByRole('img')).toBeNull()
    const hiders = screen.getByRole('region', { name: 'Hiders' })
    expect(within(hiders).getAllByRole('img', { name: 'No fix yet' })).toHaveLength(2)
  })

  it('shows unassigned lobby players in their own section without bars', () => {
    renderBoard(
      view([row('me', 'Casey', 'unassigned'), row('u2', 'Riley', 'unassigned')], {
        phase: 'lobby',
        you: { player_id: 'me', role: 'unassigned', status: 'active', is_host: true },
      }),
    )
    expect(screen.getByRole('region', { name: 'Not on a team yet' })).toBeInTheDocument()
    expect(screen.queryByRole('img')).toBeNull()
  })

  it('handles empty and one-letter names and a name with an apostrophe', () => {
    renderBoard(
      view([
        row('me', '', 'hider'),
        row('h2', 'x', 'hider'),
        row('h3', 'Ryan O\u2019Donnell', 'hider'),
      ]),
    )
    expect(screen.getByText(/Ryan O\u2019Donnell/)).toBeInTheDocument()
    expect(screen.getByText('?')).toBeInTheDocument()
    expect(screen.getByText('X')).toBeInTheDocument()
    expect(screen.getByText('RO')).toBeInTheDocument()
  })

  it('renders a 27 player roster', () => {
    const players = Array.from({ length: 27 }, (_, i) =>
      row(i === 0 ? 'me' : `p${i}`, `Sam Smith ${i}`, i % 4 === 0 ? 'seeker' : 'hider'),
    )
    renderBoard(view(players, { you: { player_id: 'me', role: 'seeker', status: 'active', is_host: false } }))
    expect(screen.getAllByRole('listitem')).toHaveLength(27)
  })

  it('shows a signal-lost player as one bar with last fix age', () => {
    renderBoard(
      view([
        row('me', 'Casey', 'hider'),
        row('h2', 'Hana Hill', 'hider', {
          status: 'signal_lost',
          location: { lat: 1, lon: 1, accuracy_m: 5, at: at(90), kind: 'last_known' },
        }),
      ]),
    )
    expect(
      screen.getByRole('img', { name: 'Signal lost, last fix 1 minute ago' }),
    ).toBeInTheDocument()
  })
})
