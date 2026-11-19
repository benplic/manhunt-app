import { beforeEach, describe, expect, it, vi } from 'vitest'
import { randomizeRoles, startGame } from './games'

describe('lobby game actions', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it('POSTs seeker_count: 1 to /roles', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        game_id: 'game-1',
        join_code: 'ABCDEF',
        phase: 'lobby',
        you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
        players: [],
      }),
    })
    vi.stubGlobal('fetch', fetchMock)

    await randomizeRoles({ token: 'tok', gameId: 'game-1', seekerCount: 1 })

    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/games\/game-1\/roles$/)
    expect(JSON.parse(init.body)).toEqual({ seeker_count: 1 })
    expect(init.headers.Authorization).toBe('Bearer tok')
  })

  it('POSTs /start and returns the player view', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        game_id: 'game-1',
        join_code: 'ABCDEF',
        phase: 'head_start',
        you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
        players: [],
      }),
    })
    vi.stubGlobal('fetch', fetchMock)

    const view = await startGame({ token: 'tok', gameId: 'game-1' })
    expect(view.phase).toBe('head_start')
    expect(String(fetchMock.mock.calls[0][0])).toMatch(/\/v1\/games\/game-1\/start$/)
  })
})
