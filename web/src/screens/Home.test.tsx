import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { Home } from './Home'

const createGame = vi.fn()
const joinGame = vi.fn()

vi.mock('../api/games', () => ({
  createGame: (...args: unknown[]) => createGame(...args),
  joinGame: (...args: unknown[]) => joinGame(...args),
}))

vi.mock('../auth/storage', () => ({
  loadSession: () => ({
    accessToken: 'tok',
    refreshToken: 'ref',
    displayName: 'Casey',
    userId: 'u1',
  }),
  clearSession: vi.fn(),
}))

describe('Home screen', () => {
  beforeEach(() => {
    createGame.mockReset()
    joinGame.mockReset()
    vi.unstubAllGlobals()
  })

  it('creates a game with the current GPS fix', async () => {
    const user = userEvent.setup()
    vi.stubGlobal('navigator', {
      geolocation: {
        getCurrentPosition: (success: PositionCallback) => {
          success({
            coords: {
              latitude: 40.66,
              longitude: -73.96,
              accuracy: 12,
              altitude: null,
              altitudeAccuracy: null,
              heading: null,
              speed: null,
              toJSON() {
                return {}
              },
            },
            timestamp: Date.now(),
            toJSON() {
              return {}
            },
          } as GeolocationPosition)
        },
      },
    })
    createGame.mockResolvedValue({
      game_id: 'game-1',
      join_code: 'ABCDEF',
      phase: 'lobby',
      you: { player_id: 'u1', role: 'hider', status: 'active', is_host: true },
      players: [],
    })

    render(<Home onSignedOut={() => undefined} onEnteredGame={() => undefined} />)
    await user.click(screen.getByRole('button', { name: /create game/i }))

    await waitFor(() => {
      expect(createGame).toHaveBeenCalledWith({
        token: 'tok',
        lat: 40.66,
        lon: -73.96,
      })
      expect(screen.getByText(/ABCDEF/)).toBeInTheDocument()
    })
  })

  it('joins with a code', async () => {
    const user = userEvent.setup()
    joinGame.mockResolvedValue({
      game_id: 'game-2',
      join_code: 'ZZZZZZ',
      phase: 'lobby',
      you: { player_id: 'u2', role: 'hider', status: 'active', is_host: false },
      players: [],
    })

    render(<Home onSignedOut={() => undefined} onEnteredGame={() => undefined} />)
    await user.type(screen.getByLabelText(/join code/i), 'zzzzzz')
    await user.click(screen.getByRole('button', { name: /^join$/i }))

    await waitFor(() => {
      expect(joinGame).toHaveBeenCalledWith({ token: 'tok', joinCode: 'ZZZZZZ' })
      expect(screen.getByText(/ZZZZZZ/)).toBeInTheDocument()
    })
  })
})
