import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createGame, joinGame } from './games'

describe('createGame', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it('creates a fresh 400m circle arena then a classic game and returns the player view', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          id: 'arena-1',
          name: 'Park circle',
          boundary: [],
          boundary_circle: { center: { lat: 40.66, lon: -73.96 }, radius_m: 400 },
          zones: [],
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ id: 'game-1', join_code: 'ABCDEF', status: 'lobby' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          game_id: 'game-1',
          join_code: 'ABCDEF',
          phase: 'lobby',
          you: {
            player_id: 'u1',
            role: 'hider',
            status: 'active',
            is_host: true,
          },
          players: [],
        }),
      })
    vi.stubGlobal('fetch', fetchMock)

    const view = await createGame({
      token: 'tok',
      lat: 40.66,
      lon: -73.96,
    })

    expect(view.game_id).toBe('game-1')
    expect(view.join_code).toBe('ABCDEF')
    expect(fetchMock).toHaveBeenCalledTimes(3)

    const [arenaUrl, arenaInit] = fetchMock.mock.calls[0]
    expect(String(arenaUrl)).toMatch(/\/v1\/arenas$/)
    expect(arenaInit.headers.Authorization).toBe('Bearer tok')
    const arenaBody = JSON.parse(arenaInit.body)
    expect(arenaBody.boundary_circle).toEqual({
      center: { lat: 40.66, lon: -73.96 },
      radius_m: 400,
    })
    expect(arenaBody.zones).toEqual([])

    const [gameUrl, gameInit] = fetchMock.mock.calls[1]
    expect(String(gameUrl)).toMatch(/\/v1\/games$/)
    expect(JSON.parse(gameInit.body)).toEqual({
      arena_id: 'arena-1',
      preset_id: 'classic',
      overrides: {
        zone_policy: { oob_countdown: 60 },
      },
    })

    const [viewUrl, viewInit] = fetchMock.mock.calls[2]
    expect(String(viewUrl)).toMatch(/\/v1\/games\/game-1$/)
    expect(viewInit.method ?? 'GET').toBe('GET')
    expect(viewInit.headers.Authorization).toBe('Bearer tok')
  })
})

describe('joinGame', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it('joins by code then GETs the player view', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ id: 'game-2', join_code: 'ZZZZZZ', status: 'lobby' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          game_id: 'game-2',
          join_code: 'ZZZZZZ',
          phase: 'lobby',
          you: {
            player_id: 'u2',
            role: 'hider',
            status: 'active',
            is_host: false,
          },
          players: [],
        }),
      })
    vi.stubGlobal('fetch', fetchMock)

    const view = await joinGame({ token: 'tok', joinCode: 'zzzzzz' })
    expect(view.game_id).toBe('game-2')

    const [, joinInit] = fetchMock.mock.calls[0]
    expect(JSON.parse(joinInit.body)).toEqual({ join_code: 'zzzzzz' })
    expect(String(fetchMock.mock.calls[1][0])).toMatch(/\/v1\/games\/game-2$/)
  })
})
