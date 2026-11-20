import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { Lobby } from './Lobby'

const randomizeRoles = vi.fn()
const startGame = vi.fn()
const setManualRoles = vi.fn()
const setLobbyCircle = vi.fn()
const removeLobbyPlayer = vi.fn()

vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,join'),
  },
}))

vi.mock('../api/games', () => ({
  DEFAULT_ARENA_RADIUS_M: 400,
  randomizeRoles: (...args: unknown[]) => randomizeRoles(...args),
  startGame: (...args: unknown[]) => startGame(...args),
  setManualRoles: (...args: unknown[]) => setManualRoles(...args),
  setLobbyCircle: (...args: unknown[]) => setLobbyCircle(...args),
  removeLobbyPlayer: (...args: unknown[]) => removeLobbyPlayer(...args),
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
  arena: {
    boundary_circle: { center: { lat: 40.66, lon: -73.96 }, radius_m: 400 },
  },
  ...overrides,
})

describe('Lobby screen', () => {
  beforeEach(() => {
    randomizeRoles.mockReset()
    startGame.mockReset()
    setManualRoles.mockReset()
    setLobbyCircle.mockReset()
    removeLobbyPlayer.mockReset()
  })

  it('shows the join code, join QR, and players', async () => {
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
    await waitFor(() => {
      expect(screen.getByAltText(/join qr for abcdef/i)).toBeInTheDocument()
    })
  })

  it('host Start randomizes when roles are incomplete then starts', async () => {
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

  it('host can assign roles manually without randomize on start', async () => {
    const user = userEvent.setup()
    const onView = vi.fn()
    const assigned = lobbyView({
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
    })
    setManualRoles.mockResolvedValue(assigned)
    startGame.mockResolvedValue(lobbyView({ ...assigned, phase: 'head_start' }))

    const { rerender } = render(
      <Lobby
        view={lobbyView()}
        onView={onView}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    await user.click(screen.getAllByRole('button', { name: /^seeker$/i })[0])
    await waitFor(() => expect(setManualRoles).toHaveBeenCalled())
    rerender(
      <Lobby
        view={assigned}
        onView={onView}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    await user.click(screen.getByRole('button', { name: /^start$/i }))
    await waitFor(() => {
      expect(randomizeRoles).not.toHaveBeenCalled()
      expect(startGame).toHaveBeenCalled()
    })
  })

  it('shows rules summary from timers', () => {
    render(
      <Lobby
        view={lobbyView({
          timers: {
            time_limit_s: 1800,
            head_start_s: 60,
            reveal_interval_s: 90,
          },
        })}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    expect(screen.getByText(/30 min · 1:00 head start · 1:30 pings/i)).toBeInTheDocument()
  })

  it('host can remove another player', async () => {
    const user = userEvent.setup()
    const onView = vi.fn()
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true)
    removeLobbyPlayer.mockResolvedValue(lobbyView({ players: [lobbyView().players[0]] }))
    render(
      <Lobby
        view={lobbyView()}
        onView={onView}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
      />,
    )
    await user.click(screen.getByRole('button', { name: /^remove$/i }))
    await waitFor(() => {
      expect(removeLobbyPlayer).toHaveBeenCalledWith({
        token: 'tok',
        gameId: 'game-1',
        playerId: 'u2',
      })
      expect(onView).toHaveBeenCalled()
    })
    confirmSpy.mockRestore()
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
