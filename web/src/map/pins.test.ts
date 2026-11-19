import { describe, expect, it } from 'vitest'
import type { PlayerView } from '../api/types'
import { pinsFromView } from './pins'

describe('pinsFromView', () => {
  it('keeps server display names and skips players without a location', () => {
    const view: PlayerView = {
      game_id: 'g',
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
        {
          player_id: 'u2',
          display_name: 'Player',
          role: 'hider',
          status: 'active',
          is_host: false,
          location: null,
        },
        {
          player_id: 'u3',
          display_name: 'Anon',
          role: 'hider',
          status: 'active',
          is_host: false,
          location: {
            lat: 40.2,
            lon: -73.2,
            accuracy_m: 8,
            at: '2099-01-01T00:00:00Z',
            kind: 'exact',
          },
        },
      ],
    }

    expect(pinsFromView(view)).toEqual([
      {
        playerId: 'u1',
        displayName: 'Casey',
        role: 'seeker',
        lat: 40.1,
        lon: -73.1,
        isYou: true,
      },
      {
        playerId: 'u3',
        displayName: 'Anon',
        role: 'hider',
        lat: 40.2,
        lon: -73.2,
        isYou: false,
      },
    ])
  })
})
