import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
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
    bindPopup: vi.fn().mockReturnThis(),
    setPopupContent: vi.fn().mockReturnThis(),
    openPopup: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  }
  const circle = {
    addTo: vi.fn().mockReturnThis(),
    setLatLng: vi.fn().mockReturnThis(),
    setRadius: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  }
  return {
    default: {
      map: vi.fn(() => map),
      tileLayer: vi.fn(() => ({ addTo: vi.fn() })),
      marker: vi.fn(() => marker),
      circle: vi.fn(() => circle),
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
    expect(screen.getByText(/outside the play circle — 12s/i)).toBeInTheDocument()
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
})
