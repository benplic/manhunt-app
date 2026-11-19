/** Snake_case shapes matching the FastAPI JSON wire format. */

export type UserDTO = {
  id: string
  display_name: string
  avatar_url: string | null
}

export type AuthOut = {
  access_token: string
  expires_at: string
  user: UserDTO
  refresh_token: string | null
}

export type ApiErrorBody = {
  error: {
    code: string
    message: string
    details?: unknown
  }
}

export type ArenaOut = {
  id: string
  name: string
  boundary: Array<{ lat: number; lon: number }>
  boundary_circle?: {
    center: { lat: number; lon: number }
    radius_m: number
  } | null
  zones: unknown[]
  version?: number
}

export type GameCreated = {
  id: string
  join_code: string
  status: string
}

/** Minimal player view fields needed for create/join MVP. */
export type PlayerView = {
  game_id: string
  join_code: string
  phase: string
  you: {
    player_id: string
    role: string
    status: string
    is_host: boolean
  }
  players: Array<{
    player_id: string
    display_name: string
    role: string
    status: string
    is_host: boolean
    location?: {
      lat: number
      lon: number
      accuracy_m: number
      at: string
      kind: string
    } | null
  }>
}
