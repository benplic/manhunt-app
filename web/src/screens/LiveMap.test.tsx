import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { PlayerView } from '../api/types'
import { LiveMap } from './LiveMap'

vi.mock('leaflet', () => {
  const map = {
    setView: vi.fn().mockReturnThis(),
    remove: vi.fn(),
    fitBounds: vi.fn(),
  }
  const marker = {
    addTo: vi.fn().mockReturnThis(),
    setLatLng: vi.fn().mockReturnThis(),
    bindPopup: vi.fn().mockReturnThis(),
    setPopupContent: vi.fn().mockReturnThis(),
    openPopup: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  }
  return {
    default: {
      map: vi.fn(() => map),
      tileLayer: vi.fn(() => ({ addTo: vi.fn() })),
      marker: vi.fn(() => marker),
      latLngBounds: vi.fn(() => ({ pad: vi.fn().mockReturnValue({}) })),
      Icon: { Default: { mergeOptions: vi.fn(), prototype: { options: {} } } },
    },
  }
})

vi.mock('../map/leafletIcons', () => ({
  ensureLeafletDefaultIcons: vi.fn(),
}))

const view: PlayerView = {
  game_id: 'game-1',
  join_code: 'ABCDEF',
  phase: 'active',
  you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
  players: [
    {
      player_id: 'u1',
      display_name: 'Casey',
      role: 'seeker',
      status: 'active',
      is_host: true,
      location: {
        lat: 40.1,
        lon: -73.1,
        accuracy_m: 5,
        at: '2099-01-01T00:00:00Z',
        kind: 'exact',
      },
    },
  ],
}

describe('LiveMap', () => {
  it('watches visible GPS and offers Scan QR / End for a host seeker', async () => {
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

    expect(screen.getByText(/live map/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /scan qr/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /end hunt/i })).toBeInTheDocument()
    await waitFor(() => {
      expect(watchLocation).toHaveBeenCalled()
    })
  })
})
