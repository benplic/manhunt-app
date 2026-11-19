import { apiRequest } from './client'
import type { ArenaOut, GameCreated, PlayerView } from './types'

/** Always mint a new play circle at the host GPS. Do not reuse prior arenas. */
export const DEFAULT_ARENA_RADIUS_M = 400

export type CreateGameInput = {
  token: string
  lat: number
  lon: number
  radiusM?: number
}

export async function createGame(input: CreateGameInput): Promise<PlayerView> {
  const radiusM = input.radiusM ?? DEFAULT_ARENA_RADIUS_M
  const arena = await apiRequest<ArenaOut>('/v1/arenas', {
    method: 'POST',
    token: input.token,
    body: {
      name: 'Park circle',
      boundary: [],
      boundary_circle: {
        center: { lat: input.lat, lon: input.lon },
        radius_m: radiusM,
      },
      zones: [],
    },
  })

  const created = await apiRequest<GameCreated>('/v1/games', {
    method: 'POST',
    token: input.token,
    body: {
      arena_id: arena.id,
      preset_id: 'classic',
      overrides: {},
    },
  })

  return apiRequest<PlayerView>(`/v1/games/${created.id}`, {
    method: 'GET',
    token: input.token,
  })
}

export type JoinGameInput = {
  token: string
  joinCode: string
}

export async function joinGame(input: JoinGameInput): Promise<PlayerView> {
  const created = await apiRequest<GameCreated>('/v1/games/join', {
    method: 'POST',
    token: input.token,
    body: { join_code: input.joinCode.trim() },
  })

  return apiRequest<PlayerView>(`/v1/games/${created.id}`, {
    method: 'GET',
    token: input.token,
  })
}
