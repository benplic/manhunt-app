import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  ackSafety,
  fetchGameEvents,
  purchasePowerUp,
  removeLobbyPlayer,
  tauntGame,
} from './games'

const playerView = {
  game_id: 'g1',
  join_code: 'ABCDEF',
  phase: 'active',
  you: {
    player_id: 'p1',
    role: 'hider',
    status: 'active',
    is_host: false,
    taunt_cooldown_s: 0,
    taunt_enabled: true,
  },
  players: [],
}

describe('friend-parity game API', () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it('POSTs taunt and returns the player view', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ ...playerView, you: { ...playerView.you, taunt_cooldown_s: 30 } }),
    })
    vi.stubGlobal('fetch', fetchMock)

    const view = await tauntGame({ token: 'tok', gameId: 'g1' })

    expect(view.you.taunt_cooldown_s).toBe(30)
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/games\/g1\/taunt$/)
    expect(init.method).toBe('POST')
    expect(init.headers.Authorization).toBe('Bearer tok')
  })

  it('POSTs remove player', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => playerView,
    })
    vi.stubGlobal('fetch', fetchMock)

    await removeLobbyPlayer({ token: 'tok', gameId: 'g1', playerId: 'p2' })

    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/games\/g1\/players\/p2\/remove$/)
    expect(init.method).toBe('POST')
    expect(init.headers.Authorization).toBe('Bearer tok')
  })

  it('POSTs power-up purchase with id and optional target', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => playerView,
    })
    vi.stubGlobal('fetch', fetchMock)

    await purchasePowerUp({
      token: 'tok',
      gameId: 'g1',
      id: 'decoy',
      lat: 40.66,
      lon: -73.96,
    })

    const [, init] = fetchMock.mock.calls[0]
    expect(JSON.parse(init.body)).toEqual({
      id: 'decoy',
      lat: 40.66,
      lon: -73.96,
    })
  })

  it('GETs /events as timeline', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        events: [{ seq: 1, type: 'tag', payload: { text: 'Tagged Alex' } }],
      }),
    })
    vi.stubGlobal('fetch', fetchMock)

    const { events } = await fetchGameEvents({ token: 'tok', gameId: 'g1' })

    expect(events).toHaveLength(1)
    expect(events[0].type).toBe('tag')
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/games\/g1\/events$/)
    expect(init.method ?? 'GET').toBe('GET')
  })

  it('POSTs safety ack and returns the player view', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => playerView,
    })
    vi.stubGlobal('fetch', fetchMock)

    await ackSafety({ token: 'tok', gameId: 'g1' })

    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/games\/g1\/safety\/ack$/)
    expect(init.method).toBe('POST')
  })
})