import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { LiveMap } from './LiveMap'

vi.mock('../geo/wakeLock', () => ({
  requestHuntWakeLock: vi.fn(async () => () => undefined),
}))

vi.mock('../map/arenaCamera', () => ({
  fitArenaOnce: vi.fn(),
  recenterOnArena: vi.fn(),
}))

vi.mock('leaflet', () => {
  const map = {
    setView: vi.fn().mockReturnThis(),
    remove: vi.fn(),
    fitBounds: vi.fn(),
    invalidateSize: vi.fn(),
  }
  const marker = {
    addTo: vi.fn().mockReturnThis(),
    setLatLng: vi.fn().mockReturnThis(),
    getLatLng: vi.fn(() => ({ lat: 40.1, lng: -73.1 })),
    bindPopup: vi.fn().mockReturnThis(),
    setPopupContent: vi.fn().mockReturnThis(),
    openPopup: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  }
  const path = {
    addTo: vi.fn().mockReturnThis(),
    setLatLng: vi.fn().mockReturnThis(),
    setLatLngs: vi.fn().mockReturnThis(),
    setRadius: vi.fn().mockReturnThis(),
    setStyle: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  }
  class FakeCircle {
    addTo = path.addTo
    setLatLng = path.setLatLng
    setRadius = path.setRadius
    setStyle = path.setStyle
    remove = path.remove
  }
  class FakePolygon {
    addTo = path.addTo
    setLatLngs = path.setLatLngs
    setStyle = path.setStyle
    remove = path.remove
  }
  return {
    default: {
      map: vi.fn(() => map),
      tileLayer: vi.fn(() => ({ addTo: vi.fn() })),
      marker: vi.fn(() => marker),
      circle: vi.fn(() => new FakeCircle()),
      polygon: vi.fn(() => new FakePolygon()),
      Circle: FakeCircle,
      Polygon: FakePolygon,
      latLng: vi.fn(() => ({ toBounds: vi.fn().mockReturnValue({}) })),
      latLngBounds: vi.fn(() => ({ pad: vi.fn().mockReturnValue({}) })),
      Icon: { Default: { mergeOptions: vi.fn(), prototype: { options: {} } } },
    },
  }
})

vi.mock('../map/leafletIcons', () => ({
  ensureLeafletDefaultIcons: vi.fn(),
}))

vi.mock('./QrShow', () => ({
  QrShow: ({ onClose }: { onClose: () => void }) => (
    <button type="button" onClick={onClose}>
      Close show
    </button>
  ),
}))

const tauntGame = vi.fn()

vi.mock('../api/games', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/games')>()
  return { ...actual, tauntGame: (...args: unknown[]) => tauntGame(...args) }
})

vi.mock('../api/session', () => ({
  withAuthRetry: async (fn: (token: string) => Promise<unknown>) => fn('tok'),
  SessionExpiredError: class SessionExpiredError extends Error {},
}))

vi.mock('./QrScan', () => ({
  QrScan: ({ onClose }: { onClose: () => void }) => (
    <button type="button" onClick={onClose}>
      Close scan
    </button>
  ),
}))

const view: PlayerView = {
  game_id: 'game-1',
  join_code: 'ABCDEF',
  phase: 'active',
  phase_remaining_s: null,
  time_limit_remaining_s: 1785,
  game_elapsed_s: 75,
  timers: { next_reveal_in_s: 40 },
  you: {
    player_id: 'u1',
    role: 'seeker',
    status: 'active',
    is_host: true,
    points: 10,
    hint: 'Warm · 40 m',
  },
  players: [
    {
      player_id: 'u1',
      display_name: 'Casey',
      role: 'seeker',
      status: 'active',
      is_host: true,
      points: 10,
      location: {
        lat: 40.1,
        lon: -73.1,
        accuracy_m: 5,
        at: '2099-01-01T00:00:00Z',
        kind: 'exact',
      },
    },
  ],
  arena: {
    boundary_circle: { center: { lat: 40.1, lon: -73.1 }, radius_m: 400 },
  },
  banners: [],
  reveals: [],
}

describe('LiveMap', () => {
  beforeEach(() => {
    tauntGame.mockReset()
    window.localStorage.clear()
  })

  it('watches visible GPS and offers Scan tag / End for a host seeker', async () => {
    const sendLocation = vi.fn()
    const watchLocation = vi.fn().mockReturnValue(() => undefined)
    const socket = { sendLocation } as never

    render(
      <LiveMap
        view={view}
        socket={socket}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={watchLocation}
      />,
    )

    expect(screen.getByText(/^seeker$/i)).toBeInTheDocument()
    expect(screen.getByText(/hunt 29:45/i)).toBeInTheDocument()
    expect(screen.getByText(/ping 0:40/i)).toBeInTheDocument()
    expect(screen.getByText(/warm · 40 m/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /scan tag/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /end hunt/i })).toBeInTheDocument()
    await waitFor(() => {
      expect(watchLocation).toHaveBeenCalled()
    })
  })

  it('shows head-start countdown and out-of-bounds warning', () => {
    const headStart: PlayerView = {
      ...view,
      phase: 'head_start',
      phase_remaining_s: 45,
      time_limit_remaining_s: 1800,
      you: {
        ...view.you,
        role: 'hider',
        is_host: false,
        bounds: { phase: 'countdown', remaining_s: 12 },
      },
    }
    render(
      <LiveMap
        view={headStart}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken="tok"
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.getByText(/head start 0:45/i)).toBeInTheDocument()
    expect(screen.getByText(/outside the play area — 12s/i)).toBeInTheDocument()
  })

  it('renders a polygon play area without a boundary_circle', async () => {
    const L = await import('leaflet')
    const polygonArena: PlayerView = {
      ...view,
      arena: {
        boundary: [
          { lat: 40.1, lon: -73.1 },
          { lat: 40.12, lon: -73.1 },
          { lat: 40.12, lon: -73.08 },
          { lat: 40.1, lon: -73.08 },
        ],
      },
    }
    render(
      <LiveMap
        view={polygonArena}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(document.querySelector('.map-frame')).toBeTruthy()
    expect(screen.getByText(/yellow play area/i)).toBeInTheDocument()
    expect(L.default.polygon).toHaveBeenCalled()
    expect(screen.getByRole('button', { name: /recenter/i })).toBeInTheDocument()
  })

  it('draws seeker spawn during head start and drops it when active', async () => {
    const L = await import('leaflet')
    const spawnZone = {
      id: 'spawn-1',
      name: 'Gate',
      kind: 'seeker_spawn' as const,
      shape: {
        type: 'polygon' as const,
        vertices: [
          { lat: 40.11, lon: -73.11 },
          { lat: 40.112, lon: -73.11 },
          { lat: 40.112, lon: -73.108 },
        ],
      },
    }
    const headStart: PlayerView = {
      ...view,
      phase: 'head_start',
      phase_remaining_s: 30,
      seeker_lock: 'spawn_zone',
      arena: {
        boundary_circle: { center: { lat: 40.1, lon: -73.1 }, radius_m: 400 },
        zones: [spawnZone],
      },
    }
    const { rerender } = render(
      <LiveMap
        view={headStart}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    const polygonsDuring = vi.mocked(L.default.polygon).mock.calls.length
    expect(polygonsDuring).toBeGreaterThan(0)

    rerender(
      <LiveMap
        view={{ ...headStart, phase: 'active', phase_remaining_s: null }}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    // Spawn layer is removed; no extra polygon for spawn after active.
    expect(vi.mocked(L.default.polygon).mock.calls.length).toBe(polygonsDuring)
  })

  it('hides Scan tag during head start so a late claim cannot land on active', () => {
    const headStart: PlayerView = {
      ...view,
      phase: 'head_start',
      phase_remaining_s: 20,
      you: { ...view.you, role: 'seeker', is_host: true },
    }
    render(
      <LiveMap
        view={headStart}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.queryByRole('button', { name: /scan tag/i })).not.toBeInTheDocument()
    expect(screen.getByText(/cannot tag until head start ends/i)).toBeInTheDocument()
  })

  it('keeps the map frame mounted under the Scan tag overlay', async () => {
    const user = userEvent.setup()
    const socket = { sendLocation: vi.fn() } as never
    render(
      <LiveMap
        view={view}
        socket={socket}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    const frame = document.querySelector('.map-frame')
    expect(frame).toBeTruthy()
    await user.click(screen.getByRole('button', { name: /scan tag/i }))
    expect(document.querySelector('.map-frame')).toBe(frame)
    expect(screen.getByRole('button', { name: /close scan/i })).toBeInTheDocument()
  })

  it('keeps the map frame after head start ends', () => {
    const headStart: PlayerView = {
      ...view,
      phase: 'head_start',
      phase_remaining_s: 1,
      you: { ...view.you, role: 'seeker', is_host: true },
    }
    const { rerender } = render(
      <LiveMap
        view={headStart}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    const frame = document.querySelector('.map-frame')
    expect(frame).toBeTruthy()
    expect(frame?.classList.contains('map-frame--hidden')).toBe(false)

    rerender(
      <LiveMap
        view={{ ...headStart, phase: 'active', phase_remaining_s: null, time_limit_remaining_s: 1799 }}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(document.querySelector('.map-frame')).toBe(frame)
    expect(frame?.classList.contains('map-frame--hidden')).toBe(false)
    expect(screen.getByText(/hunt 29:59/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /scan tag/i })).toBeInTheDocument()
  })

  it('lets an active hider taunt and refreshes the view', async () => {
    const user = userEvent.setup()
    const onView = vi.fn()
    tauntGame.mockResolvedValue({
      ...view,
      you: { ...view.you, role: 'hider', is_host: false, taunt_cooldown_s: 15 },
    })
    const hider: PlayerView = {
      ...view,
      you: {
        ...view.you,
        role: 'hider',
        is_host: false,
        taunt_cooldown_s: 0,
        taunt_enabled: true,
      },
    }
    render(
      <LiveMap
        view={hider}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken="tok"
        note={null}
        onView={onView}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.queryByRole('button', { name: /^taunt$/i })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /^taunt$/i }))
    await waitFor(() => expect(tauntGame).toHaveBeenCalled())
    expect(onView).toHaveBeenCalled()
  })

  it('does not show taunt for seekers', () => {
    render(
      <LiveMap
        view={view}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.queryByRole('button', { name: /taunt/i })).not.toBeInTheDocument()
  })

  it('does not publish a location while the safety gate is up', () => {
    const sendLocation = vi.fn()
    const watchLocation = vi.fn().mockReturnValue(() => undefined)
    render(
      <LiveMap
        view={view}
        socket={{ sendLocation } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={watchLocation}
        holdPresence
      />,
    )
    expect(watchLocation).not.toHaveBeenCalled()
    expect(sendLocation).not.toHaveBeenCalled()
  })

  it('renders a server hint object instead of crashing the live screen', () => {
    const hinted: PlayerView = {
      ...view,
      you: {
        ...view.you,
        role: 'seeker',
        hint: { band: 'hot', meters: 30, name: 'Riley', bearing_deg: 0 },
      },
    }
    render(
      <LiveMap
        view={hinted}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.getByText(/riley is hot, 30 m, n/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /leave/i })).toBeInTheDocument()
    expect(document.querySelector('.live-map--stacked')).toBeTruthy()
  })

  it('shows going-dark copy when this player is signal_lost', () => {
    const dark: PlayerView = {
      ...view,
      you: { ...view.you, status: 'signal_lost', role: 'hider', is_host: false },
    }
    render(
      <LiveMap
        view={dark}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken="tok"
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.getByText(/you went dark/i)).toBeInTheDocument()
  })

  it('masks a blocked name on the leaderboard and shows shield remaining', async () => {
    const user = userEvent.setup()
    const blocked: PlayerView = {
      ...view,
      active_effects: [
        {
          type: 'shield',
          owner_id: 'hider-1',
          display_name: 'Riley',
          remaining_s: 18,
        },
      ],
      players: [
        ...view.players,
        {
          player_id: 'hider-1',
          display_name: 'Riley',
          role: 'hider',
          status: 'active',
          is_host: false,
          points: 40,
        },
      ],
    }
    render(
      <LiveMap
        view={blocked}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken={null}
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.getByText(/shield · riley · 0:18/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /scores/i }))
    expect(screen.getByText('Riley')).toBeInTheDocument()
    const blockButtons = screen.getAllByRole('button', { name: /^block$/i })
    await user.click(blockButtons[0])
    expect(screen.getByText(/blocked player #1/i)).toBeInTheDocument()
    expect(screen.queryByText('Riley')).not.toBeInTheDocument()
  })

  it('shows you are out and hides Show tag when eliminated', () => {
    const out: PlayerView = {
      ...view,
      you: { ...view.you, role: 'hider', status: 'eliminated', is_host: false },
    }
    render(
      <LiveMap
        view={out}
        socket={{ sendLocation: vi.fn() } as never}
        qrToken="tok"
        note={null}
        onView={() => undefined}
        onLeave={() => undefined}
        onSignedOut={() => undefined}
        watchLocation={() => () => undefined}
      />,
    )
    expect(screen.getByText(/you.?re out/i)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /show tag/i })).not.toBeInTheDocument()
  })
})
