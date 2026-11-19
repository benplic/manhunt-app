import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import { Home } from './Home'

const createGame = vi.fn()
const joinGame = vi.fn()
const refreshAccessToken = vi.fn()
const clearSession = vi.fn()

vi.mock('../api/games', () => ({
  createGame: (...args: unknown[]) => createGame(...args),
  joinGame: (...args: unknown[]) => joinGame(...args),
}))

vi.mock('../api/auth', () => ({
  refreshAccessToken: (...args: unknown[]) => refreshAccessToken(...args),
}))

vi.mock('../auth/storage', () => ({
  loadSession: () => ({
    accessToken: 'tok',
    refreshToken: 'ref',
    displayName: 'Casey',
    userId: 'u1',
  }),
  clearSession: (...args: unknown[]) => clearSession(...args),
}))

describe('Home screen', () => {
  beforeEach(() => {
    createGame.mockReset()
    joinGame.mockReset()
    refreshAccessToken.mockReset()
    clearSession.mockReset()
    vi.unstubAllGlobals()
  })

  it('creates a game with a fresh GPS fix', async () => {
    const user = userEvent.setup()
    const onEnteredGame = vi.fn()
    const getCurrentPosition = vi.fn((success: PositionCallback) => {
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
    })
    vi.stubGlobal('navigator', {
      geolocation: { getCurrentPosition },
    })
    createGame.mockResolvedValue({
      game_id: 'game-1',
      join_code: 'ABCDEF',
      phase: 'lobby',
      you: { player_id: 'u1', role: 'hider', status: 'active', is_host: true },
      players: [],
    })

    render(<Home onSignedOut={() => undefined} onEnteredGame={onEnteredGame} />)
    await user.click(screen.getByRole('button', { name: /create game/i }))

    await waitFor(() => {
      expect(getCurrentPosition).toHaveBeenCalledWith(
        expect.any(Function),
        expect.any(Function),
        expect.objectContaining({ maximumAge: 0 }),
      )
      expect(createGame).toHaveBeenCalledWith({
        token: 'tok',
        lat: 40.66,
        lon: -73.96,
      })
      expect(onEnteredGame).toHaveBeenCalledWith(expect.objectContaining({ join_code: 'ABCDEF' }))
    })
  })

  it('refreshes once then signs out when the session is dead', async () => {
    const user = userEvent.setup()
    const onSignedOut = vi.fn()
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
    createGame.mockRejectedValue(new ApiError('TOKEN_EXPIRED', 'expired', 401))
    refreshAccessToken.mockRejectedValue(new ApiError('TOKEN_INVALID', 'bad', 401))

    render(<Home onSignedOut={onSignedOut} onEnteredGame={() => undefined} />)
    await user.click(screen.getByRole('button', { name: /create game/i }))

    await waitFor(() => {
      expect(refreshAccessToken).toHaveBeenCalled()
      expect(clearSession).toHaveBeenCalled()
      expect(onSignedOut).toHaveBeenCalled()
    })
  })

  it('joins with a code', async () => {
    const user = userEvent.setup()
    const onEnteredGame = vi.fn()
    joinGame.mockResolvedValue({
      game_id: 'game-2',
      join_code: 'ZZZZZZ',
      phase: 'lobby',
      you: { player_id: 'u2', role: 'hider', status: 'active', is_host: false },
      players: [],
    })

    render(<Home onSignedOut={() => undefined} onEnteredGame={onEnteredGame} />)
    await user.type(screen.getByLabelText(/join code/i), 'zzzzzz')
    await user.click(screen.getByRole('button', { name: /^join$/i }))

    await waitFor(() => {
      expect(joinGame).toHaveBeenCalledWith({ token: 'tok', joinCode: 'ZZZZZZ' })
      expect(onEnteredGame).toHaveBeenCalledWith(expect.objectContaining({ join_code: 'ZZZZZZ' }))
    })
  })
})
