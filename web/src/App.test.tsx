import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from './api/client'
import App from './App'
import { rememberActiveGame } from './game/resume'
import { resetSafetyDisclaimerForTests } from './game/safetyDisclaimer'

const fetchGameView = vi.fn()
const leaveGame = vi.fn()
const { socketInstances } = vi.hoisted(() => ({
  socketInstances: [] as Array<{
    onView: ((view: unknown) => void) | null
    onEvent: ((event: {
      seq: number
      type: string
      text: string
      tone: string | null
      player_id: string | null
      announcement: string | null
      subject_name: string | null
    }) => void) | null
  }>,
}))

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
    onEvent: ((event: {
      seq: number
      type: string
      text: string
      tone: string | null
      player_id: string | null
      announcement: string | null
      subject_name: string | null
    }) => void) | null = null
    onRemoved: (() => void) | null = null
    lastSeq: number | undefined
    connect = vi.fn()
    disconnect = vi.fn()
    sendLocation = vi.fn()

    constructor() {
      socketInstances.push(this)
    }
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
    tagAnnouncement,
    onLeave,
  }: {
    view: { join_code: string; you: { role: string } }
    holdPresence?: boolean
    tagAnnouncement?: { text: string } | null
    onLeave: () => void
  }) => (
    <main className="live-map" data-hold={holdPresence ? 'yes' : 'no'}>
      <p className="eyebrow">
        live · {view.join_code}
      </p>
      <p className="role-pill">{view.you.role}</p>
      <button type="button">Recenter</button>
      <button type="button" onClick={onLeave}>Leave test hunt</button>
      {tagAnnouncement ? <p role="status">{tagAnnouncement.text}</p> : null}
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
    leaveGame.mockResolvedValue(undefined)
    socketInstances.length = 0
  })

  afterEach(() => {
    vi.useRealTimers()
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

  it('wires structured socket announcements FIFO for two seconds each', async () => {
    vi.useFakeTimers()
    localStorage.setItem('manhunt.safetyDisclaimerAcked', '1')
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue({ ...liveView, phase: 'active', phase_remaining_s: null })

    render(<App />)
    await act(async () => {
      await Promise.resolve()
      await Promise.resolve()
    })
    const socket = socketInstances[0]
    expect(socket.onEvent).toBeTypeOf('function')

    act(() => {
      socket.onEvent?.({
        seq: 1,
        type: 'status',
        text: 'Riley is eliminated',
        tone: null,
        player_id: 'h1',
        announcement: null,
        subject_name: null,
      })
      socket.onEvent?.({
        seq: 2,
        type: 'tag',
        text: 'untrusted prose',
        tone: 'danger',
        player_id: 'h1',
        announcement: 'player_tagged',
        subject_name: 'Riley',
      })
      socket.onEvent?.({
        seq: 3,
        type: 'out_of_bounds',
        text: 'different untrusted prose',
        tone: 'danger',
        player_id: 'h2',
        announcement: 'player_tagged_out_of_bounds',
        subject_name: 'Morgan',
      })
    })

    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')
    await act(() => vi.advanceTimersByTimeAsync(2_000))
    expect(screen.getByRole('status')).toHaveTextContent(
      'Morgan was tagged out of bounds!',
    )
    await act(() => vi.advanceTimersByTimeAsync(2_000))
    // The flash fades for 450 ms before it leaves the DOM.
    await act(() => vi.advanceTimersByTimeAsync(450))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    vi.useRealTimers()
  })

  it('expires two seconds from display across a live phase transition', async () => {
    vi.useFakeTimers()
    localStorage.setItem('manhunt.safetyDisclaimerAcked', '1')
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue({ ...liveView, phase: 'active', phase_remaining_s: null })

    render(<App />)
    await act(async () => {
      await Promise.resolve()
      await Promise.resolve()
    })
    const socket = socketInstances[0]
    act(() => {
      socket.onEvent?.({
        seq: 4,
        type: 'tag',
        text: 'ignored',
        tone: 'danger',
        player_id: 'h1',
        announcement: 'player_tagged',
        subject_name: 'Riley',
      })
    })
    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')

    await act(() => vi.advanceTimersByTimeAsync(1_000))
    act(() => {
      socket.onView?.({ ...liveView, phase: 'paused', phase_remaining_s: null })
    })
    await act(() => vi.advanceTimersByTimeAsync(999))
    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')

    await act(() => vi.advanceTimersByTimeAsync(1))
    // The flash fades for 450 ms before it leaves the DOM.
    await act(() => vi.advanceTimersByTimeAsync(450))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('shows final tag events over results for their full queued durations', async () => {
    vi.useFakeTimers()
    localStorage.setItem('manhunt.safetyDisclaimerAcked', '1')
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue({ ...liveView, phase: 'active', phase_remaining_s: null })

    render(<App />)
    await act(async () => {
      await Promise.resolve()
      await Promise.resolve()
    })
    const socket = socketInstances[0]
    act(() => {
      socket.onEvent?.({
        seq: 1,
        type: 'tag',
        text: 'ignored',
        tone: 'danger',
        player_id: 'h1',
        announcement: 'player_tagged',
        subject_name: 'Riley',
      })
      socket.onEvent?.({
        seq: 2,
        type: 'tag',
        text: 'ignored',
        tone: 'danger',
        player_id: 'h2',
        announcement: 'player_tagged',
        subject_name: 'Morgan',
      })
    })
    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')

    act(() => {
      socket.onView?.({ ...liveView, phase: 'ended', phase_remaining_s: null })
    })

    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')
    await act(() => vi.advanceTimersByTimeAsync(1_999))
    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')
    await act(() => vi.advanceTimersByTimeAsync(1))
    expect(screen.getByRole('status')).toHaveTextContent('Morgan was tagged!')
    await act(() => vi.advanceTimersByTimeAsync(2_000))
    // The flash fades for 450 ms before it leaves the DOM.
    await act(() => vi.advanceTimersByTimeAsync(450))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('clears current and queued announcements when the player leaves', async () => {
    localStorage.setItem('manhunt.safetyDisclaimerAcked', '1')
    rememberActiveGame('game-live')
    fetchGameView.mockResolvedValue({ ...liveView, phase: 'active', phase_remaining_s: null })
    const user = userEvent.setup()

    render(<App />)
    expect(await screen.findByText(/live · ABCDEF/i)).toBeInTheDocument()
    const socket = socketInstances[0]
    act(() => {
      socket.onEvent?.({
        seq: 1,
        type: 'tag',
        text: 'ignored',
        tone: 'danger',
        player_id: 'h1',
        announcement: 'player_tagged',
        subject_name: 'Riley',
      })
      socket.onEvent?.({
        seq: 2,
        type: 'tag',
        text: 'ignored',
        tone: 'danger',
        player_id: 'h2',
        announcement: 'player_tagged',
        subject_name: 'Morgan',
      })
    })
    expect(screen.getByRole('status')).toHaveTextContent('Riley was tagged!')

    await user.click(screen.getByRole('button', { name: 'Leave test hunt' }))

    expect(screen.queryByText('Riley was tagged!')).not.toBeInTheDocument()
    expect(screen.queryByText('Morgan was tagged!')).not.toBeInTheDocument()

    act(() => {
      socket.onView?.({ ...liveView, phase: 'active', phase_remaining_s: null })
    })
    expect(screen.queryByText('Riley was tagged!')).not.toBeInTheDocument()
    expect(screen.queryByText('Morgan was tagged!')).not.toBeInTheDocument()
  })
})
