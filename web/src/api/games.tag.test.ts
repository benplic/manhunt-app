import { beforeEach, describe, expect, it, vi } from 'vitest'
import { claimQrTag, endGame } from './games'

describe('claimQrTag', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it('POSTs the scanned token to /tags/qr', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ result: 'accepted' }),
    })
    vi.stubGlobal('fetch', fetchMock)

    await claimQrTag({ token: 'tok', gameId: 'game-1', qrToken: 'qr-secret' })

    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/games\/game-1\/tags\/qr$/)
    expect(JSON.parse(init.body)).toEqual({ token: 'qr-secret' })
    expect(init.headers.Authorization).toBe('Bearer tok')
  })
})

describe('endGame', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it('POSTs /end and returns the player view', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        game_id: 'game-1',
        join_code: 'ABCDEF',
        phase: 'ended',
        you: { player_id: 'u1', role: 'seeker', status: 'active', is_host: true },
        players: [],
        result: { winner: 'seekers', reason: 'host_ended', ended_at: null },
      }),
    })
    vi.stubGlobal('fetch', fetchMock)

    const view = await endGame({ token: 'tok', gameId: 'game-1' })
    expect(view.phase).toBe('ended')
    expect(view.result?.winner).toBe('seekers')
    expect(String(fetchMock.mock.calls[0][0])).toMatch(/\/v1\/games\/game-1\/end$/)
  })
})
