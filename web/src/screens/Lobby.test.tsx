import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { Lobby } from './Lobby'

const randomizeRoles = vi.fn()
const startGame = vi.fn()

vi.mock('../api/games', () => ({
  randomizeRoles: (...args: unknown[]) => randomizeRoles(...args),
  startGame: (...args: unknown[]) => startGame(...args),
}))

vi.mock('../api/session', () => ({
  withAuthRetry: async (fn: (token: string) => Promise<unknown>) => fn('tok'),
  SessionExpiredError: class SessionExpiredError extends Error {},
}))

const lobbyView = (overrides: Partial<PlayerView> = {}): PlayerView => ({
  game_id: 'game-1',
  join_code: 'ABCDEF',
  phase: 'lobby',
  you: { player_id: 'u1', role: 'hider', status: 'active', is_host: true },
  players: [
    {
      player_id: 'u1',
      display_name: 'Casey',
      role: 'hider',
      status: 'active',
      is_host: true,
    },
    {
      player_id: 'u2',
      display_name: 'Riley',
      role: 'hider',
      status: 'active',
      is_host: false,
    },
  ],
  ...overrides,
})

describe('Lobby screen', () => {
  beforeEach(() => {
    randomizeRoles.mockReset()
    startGame.mockReset()
  })

  it('shows the join code and players', () => {
    render(
      <Lobby
        view={lobbyView()}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    expect(screen.getByText(/ABCDEF/)).toBeInTheDocument()
    expect(screen.getByText(/Casey/)).toBeInTheDocument()
    expect(screen.getByText(/Riley/)).toBeInTheDocument()
  })

  it('host Start posts seeker_count 1 then start', async () => {
    const user = userEvent.setup()
    const onView = vi.fn()
    randomizeRoles.mockResolvedValue(
      lobbyView({
        you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
        players: [
          {
            player_id: 'u1',
            display_name: 'Casey',
            role: 'seeker',
            status: 'active',
            is_host: true,
          },
          {
            player_id: 'u2',
            display_name: 'Riley',
            role: 'hider',
            status: 'active',
            is_host: false,
          },
        ],
      }),
    )
    startGame.mockResolvedValue(
      lobbyView({
        phase: 'head_start',
        you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
      }),
    )

    render(
      <Lobby
        view={lobbyView()}
        onView={onView}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    await user.click(screen.getByRole('button', { name: /^start$/i }))

    await waitFor(() => {
      expect(randomizeRoles).toHaveBeenCalledWith({
        token: 'tok',
        gameId: 'game-1',
        seekerCount: 1,
      })
      expect(startGame).toHaveBeenCalledWith({ token: 'tok', gameId: 'game-1' })
      expect(onView).toHaveBeenCalledWith(
        expect.objectContaining({ phase: 'head_start' }),
      )
    })
  })

  it('hides Start for non-hosts', () => {
    render(
      <Lobby
        view={lobbyView({
          you: { player_id: 'u2', role: 'hider', status: 'active', is_host: false },
        })}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    expect(screen.queryByRole('button', { name: /^start$/i })).not.toBeInTheDocument()
    expect(screen.getByText(/waiting for host/i)).toBeInTheDocument()
  })
})
