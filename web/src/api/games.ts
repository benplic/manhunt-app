import { apiRequest } from './client'
import type { ArenaOut, GameCreated, GameEventsOut, PlayerView } from './types'

/** Always mint a new play circle at the host GPS. Do not reuse prior arenas. */
export const DEFAULT_ARENA_RADIUS_M = 400

/**
 * Web friends often join from outside the host's first GPS fix. Classic's 15 s
 * out-of-bounds countdown auto-tags hiders and ends the hunt as "All hiders
 * were tagged." Give a longer walk-in window for the browser MVP.
 */
export const WEB_OOB_COUNTDOWN_S = 60

/** Desktop tabs often pause GPS; keep silence longer than classic 45 s. */
export const WEB_SIGNAL_SILENCE_S = 180

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
      overrides: {
        zone_policy: { oob_countdown: WEB_OOB_COUNTDOWN_S },
        signal_loss: { silence: WEB_SIGNAL_SILENCE_S, penalty: 'none' },
      },
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

export type RandomizeRolesInput = {
  token: string
  gameId: string
  seekerCount?: number
}

/** Host assigns seekers. Server phase stays `lobby` until start. */
export async function randomizeRoles(input: RandomizeRolesInput): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/roles`, {
    method: 'POST',
    token: input.token,
    // API requires mode; without it the host gets "mode must be random or manual."
    body: { mode: 'random', seeker_count: input.seekerCount ?? 1 },
  })
}

export type ManualRolesInput = {
  token: string
  gameId: string
  assignments: Record<string, 'seeker' | 'hider'>
}

/** Host sets each seat explicitly (web lobby role toggles). */
export async function setManualRoles(input: ManualRolesInput): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/roles`, {
    method: 'POST',
    token: input.token,
    body: { mode: 'manual', assignments: input.assignments },
  })
}

export type SetLobbyCircleInput = {
  token: string
  gameId: string
  radiusM: number
  center?: { lat: number; lon: number }
}

/** Host resizes the play circle before Start. */
export async function setLobbyCircle(input: SetLobbyCircleInput): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/arena`, {
    method: 'POST',
    token: input.token,
    body: {
      radius_m: input.radiusM,
      ...(input.center ? { center: input.center } : {}),
    },
  })
}

export type StartGameInput = {
  token: string
  gameId: string
}

/**
 * Host starts the hunt. Verified phases after start: `head_start` or `active`
 * (classic preset uses head_start). Lobby is never returned from a successful start.
 */
export async function startGame(input: StartGameInput): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/start`, {
    method: 'POST',
    token: input.token,
  })
}

export async function leaveGame(input: { token: string; gameId: string }): Promise<void> {
  await apiRequest<{ ok: boolean }>(`/v1/games/${input.gameId}/leave`, {
    method: 'POST',
    token: input.token,
  })
}

export async function endGame(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/end`, {
    method: 'POST',
    token: input.token,
  })
}

/** Seeker claims a hider QR. Distance (30 m) is enforced server-side. Returns the seeker view. */
export async function claimQrTag(input: {
  token: string
  gameId: string
  qrToken: string
}): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/tags/qr`, {
    method: 'POST',
    token: input.token,
    body: { token: input.qrToken },
  })
}

export async function fetchGameView(input: {
  token: string
  gameId: string
}): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}`, {
    method: 'GET',
    token: input.token,
  })
}

export async function pauseGame(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/pause`, {
    method: 'POST',
    token: input.token,
  })
}

export async function resumeGame(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/resume`, {
    method: 'POST',
    token: input.token,
  })
}

export async function undoLastTag(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/tags/undo`, {
    method: 'POST',
    token: input.token,
  })
}

export async function rematchGame(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/rematch`, {
    method: 'POST',
    token: input.token,
  })
}

export async function tauntGame(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/taunt`, {
    method: 'POST',
    token: input.token,
  })
}

export async function removeLobbyPlayer(input: {
  token: string
  gameId: string
  playerId: string
}): Promise<PlayerView> {
  return apiRequest<PlayerView>(
    `/v1/games/${input.gameId}/players/${input.playerId}/remove`,
    {
      method: 'POST',
      token: input.token,
    },
  )
}

export type PurchasePowerUpInput = {
  token: string
  gameId: string
  id: string
  lat?: number
  lon?: number
  target_player_id?: string
  zone_id?: string
}

export async function purchasePowerUp(input: PurchasePowerUpInput): Promise<PlayerView> {
  const { token, gameId, id, ...extra } = input
  return apiRequest<PlayerView>(`/v1/games/${gameId}/power-ups`, {
    method: 'POST',
    token,
    body: { id, ...extra },
  })
}

export async function fetchGameEvents(input: {
  token: string
  gameId: string
}): Promise<GameEventsOut> {
  return apiRequest<GameEventsOut>(`/v1/games/${input.gameId}/events`, {
    method: 'GET',
    token: input.token,
  })
}

export async function ackSafety(input: { token: string; gameId: string }): Promise<PlayerView> {
  return apiRequest<PlayerView>(`/v1/games/${input.gameId}/safety/ack`, {
    method: 'POST',
    token: input.token,
  })
}
