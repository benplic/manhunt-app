import { describe, expect, it } from 'vitest'
import type { PlayerView } from '../api/types'
import { revealsFromView } from './reveals'

describe('revealsFromView', () => {
  it('drops expired reveals', () => {
    const view = {
      reveals: [
        {
          reveal_id: '1',
          player_id: 'p',
          lat: 1,
          lon: 2,
          radius_m: 30,
          expires_in_s: 0,
          display_name: 'Ada',
        },
        {
          reveal_id: '2',
          player_id: 'p2',
          lat: 3,
          lon: 4,
          radius_m: 30,
          expires_in_s: 8,
          display_name: 'Ben',
        },
      ],
    } as PlayerView
    expect(revealsFromView(view)).toHaveLength(1)
    expect(revealsFromView(view)[0]?.reveal_id).toBe('2')
  })
})
