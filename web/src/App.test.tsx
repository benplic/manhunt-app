import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from './api/client'
import App from './App'
import { rememberActiveGame } from './game/resume'
import { resetSafetyDisclaimerForTests } from './game/safetyDisclaimer'

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

vi.mock('./screens/LiveMap', () => ({
  LiveMap: ({
    view,
    holdPresence,
  }: {
    view: { join_code: string; you: { role: string } }
    holdPresence?: boolean
  }) => (
    <main className="live-map" data-hold={holdPresence ? 'yes' : 'no'}>
      <p className="eyebrow">
        live · {view.join_code}
      </p>
      <p className="role-pill">{view.you.role}</p>
      <button type="button">Recenter</button>
    </main>
  ),
}))

const liveView = {
  game_id: 'game-live',
  join_code: 'ABCDEF',
  phase: 'head_start',
  phase_remaining_s: 40,
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
  banners: [],
  reveals: [],
}

describe('App rejoin', () => {
  beforeEach(() => {
    sessionStorage.clear()
    localStorage.clear()
    resetSafetyDisclaimerForTests()
    fetchGameView.mockReset()
    leaveGame.mockReset()
  })

  afterEach(() => {
    sessionStorage.clear()
    localStorage.clear()
    resetSafetyDisclaimerForTests()
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
    expect(screen.getByText('ABCDEF')).toBeInTheDocument()
  })

  it('keeps the live map mounted under the safety gate and reveals it after Continue', async () => {
    const user = userEvent.setup()
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue(liveView)

    render(<App />)

    expect(await screen.findByRole('heading', { name: /play safely/i })).toBeInTheDocument()
    // Map stays mounted under the gate so Leaflet is not torn down on Continue.
    expect(screen.getByText(/live · ABCDEF/i)).toBeInTheDocument()
    expect(document.querySelector('.live-map')).toHaveAttribute('data-hold', 'yes')
    expect(screen.getByText(/^hider$/i)).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: /continue/i }))

    expect(screen.queryByRole('heading', { name: /play safely/i })).not.toBeInTheDocument()
    expect(screen.getByText(/live · ABCDEF/i)).toBeInTheDocument()
    expect(document.querySelector('.live-map')).toHaveAttribute('data-hold', 'no')
    expect(screen.getByRole('button', { name: /recenter/i })).toBeInTheDocument()
  })

  it('rejoins a live hunt straight to the map when safety was already acknowledged', async () => {
    localStorage.setItem('manhunt.safetyDisclaimerAcked', '1')
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue({ ...liveView, phase: 'active', phase_remaining_s: null })

    render(<App />)

    expect(await screen.findByText(/live · ABCDEF/i)).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: /play safely/i })).not.toBeInTheDocument()
    expect(screen.queryByText(/connecting to the hunt/i)).not.toBeInTheDocument()
  })
})
