import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from './api/client'
import App from './App'
import { rememberActiveGame } from './game/resume'

const fetchGameView = vi.fn()
const leaveGame = vi.fn()

vi.mock('./api/games', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./api/games')>()
  return {
    ...actual,
    fetchGameView: (...args: unknown[]) => fetchGameView(...args),
    leaveGame: (...args: unknown[]) => leaveGame(...args),
  }
})

vi.mock('./api/config', () => ({
  apiBaseUrl: () => 'http://localhost:8000',
}))

vi.mock('./api/ws', () => {
  class FakeSocket {
    onView: ((view: unknown) => void) | null = null
    onQr: ((token: string) => void) | null = null
    onError: ((err: { message: string }) => void) | null = null
    onRemoved: (() => void) | null = null
    lastSeq: number | undefined
    connect = vi.fn()
    disconnect = vi.fn()
    sendLocation = vi.fn()
  }
  return {
    GameSocket: FakeSocket,
    wsUrlForGame: () => 'ws://localhost:8000/v1/games/g1/ws',
  }
})

vi.mock('./auth/storage', () => ({
  loadSession: () => ({
    accessToken: 'tok',
    refreshToken: 'ref',
    displayName: 'Casey',
    userId: 'u1',
  }),
  clearSession: vi.fn(),
}))

describe('App rejoin', () => {
  beforeEach(() => {
    sessionStorage.clear()
    fetchGameView.mockReset()
    leaveGame.mockReset()
  })

  afterEach(() => {
    sessionStorage.clear()
  })

  it('lets the player cancel a hung rejoin and return home', async () => {
    const user = userEvent.setup()
    rememberActiveGame('game-stuck')
    // Never resolves — simulates a sleeping API or dead game id.
    fetchGameView.mockReturnValue(new Promise(() => undefined))

    render(<App />)

    expect(await screen.findByText(/rejoining the hunt/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /cancel rejoin/i }))

    await waitFor(() => {
      expect(screen.getByRole('heading', { name: /manhunt/i })).toBeInTheDocument()
    })
    expect(sessionStorage.getItem('manhunt.activeGameId')).toBeNull()
  })

  it('surfaces a closed-hunt note when rejoin gets GAME_NOT_FOUND', async () => {
    rememberActiveGame('game-gone')
    fetchGameView.mockRejectedValue(new ApiError('GAME_NOT_FOUND', 'Game not found.', 404))

    render(<App />)

    expect(await screen.findByRole('heading', { name: /manhunt/i })).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent(/gone or already finished/i)
    expect(sessionStorage.getItem('manhunt.activeGameId')).toBeNull()
  })

  it('finishes rejoin even when resuming flips true mid-flight', async () => {
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue({
      game_id: 'game-live',
      join_code: 'ABCDEF',
      phase: 'lobby',
      you: {
        player_id: 'u1',
        role: 'hider',
        status: 'active',
        is_host: true,
      },
      players: [
        {
          player_id: 'u1',
          display_name: 'Casey',
          role: 'hider',
          status: 'active',
          is_host: true,
        },
      ],
    })

    render(<App />)

    expect(await screen.findByText(/join code/i)).toBeInTheDocument()
    expect(screen.getByText(/ABCDEF/)).toBeInTheDocument()
  })
})
