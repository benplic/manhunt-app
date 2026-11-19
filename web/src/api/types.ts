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

export type GameResult = {
  winner: string
  reason: string
  ended_at: string | null
}

/** Minimal player view fields needed for the web MVP. */
export type PlayerView = {
  game_id: string
  join_code: string
  phase: string
  /** Seconds left in head_start (or null outside that phase). */
  phase_remaining_s?: number | null
  /** Seconds left on the hunt clock. */
  time_limit_remaining_s?: number | null
  game_elapsed_s?: number
  you: {
    player_id: string
    role: string
    status: string
    is_host: boolean
    bounds?: {
      phase: string
      remaining_s: number | null
    }
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
  arena?: {
    boundary?: Array<{ lat: number; lon: number }>
    boundary_circle?: {
      center: { lat: number; lon: number }
      radius_m: number
    } | null
  } | null
  result?: GameResult | null
}
