import { describe, expect, it } from 'vitest'
import type { PlayerView } from '../api/types'
import { pinsFromView } from './pins'

const NOW = Date.parse('2026-11-24T20:00:00Z')
const at = (secondsAgo: number) => new Date(NOW - secondsAgo * 1000).toISOString()

describe('pinsFromView', () => {
  const view: PlayerView = {
    game_id: 'g',
    join_code: 'ABCDEF',
    phase: 'active',
    timers: { reveal_interval_s: 60 },
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
          at: at(0),
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
          at: at(150),
          kind: 'exact',
        },
      },
    ],
  }

  it('keeps server display names and skips players without a location', () => {
    const pins = pinsFromView(view, NOW)
    expect(pins).toHaveLength(2)
    expect(pins[0]).toMatchObject({
      playerId: 'u1',
      displayName: 'Casey',
      opacity: 1,
    })
    expect(pins[1]).toMatchObject({
      playerId: 'u3',
      opacity: 0.5,
    })
  })

  it('shows only yourself on the map when you are eliminated', () => {
    const out: PlayerView = {
      ...view,
      you: { ...view.you, role: 'hider', status: 'eliminated' },
    }
    expect(pinsFromView(out, NOW).map((p) => p.playerId)).toEqual(['u1'])
  })
})