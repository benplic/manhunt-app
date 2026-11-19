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
    openPopup: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  }
  return {
    default: {
      map: vi.fn(() => map),
      tileLayer: vi.fn(() => ({ addTo: vi.fn() })),
      marker: vi.fn(() => marker),
      latLngBounds: vi.fn(() => ({ pad: vi.fn().mockReturnValue({}) })),
    },
  }
})

vi.mock('../auth/storage', () => ({
  loadSession: () => ({
    accessToken: 'tok',
    refreshToken: 'ref',
    displayName: 'Casey',
    userId: 'u1',
  }),
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
  it('connects the game socket and watches visible GPS', async () => {
    const connect = vi.fn()
    const disconnect = vi.fn()
    const sendLocation = vi.fn()
    const watchLocation = vi.fn().mockReturnValue(() => undefined)
    const createSocket = () =>
      ({
        connect,
        disconnect,
        sendLocation,
        onView: null,
        onQr: null,
        onError: null,
        lastSeq: undefined,
      }) as never

    render(
      <LiveMap
        view={view}
        onView={() => undefined}
        onLeave={() => undefined}
        createSocket={createSocket}
        watchLocation={watchLocation}
      />,
    )

    expect(screen.getByText(/live map/i)).toBeInTheDocument()
    await waitFor(() => {
      expect(connect).toHaveBeenCalledWith(
        expect.objectContaining({
          token: 'tok',
          url: expect.stringContaining('/v1/games/game-1/ws'),
        }),
      )
      expect(watchLocation).toHaveBeenCalled()
    })
  })
})
