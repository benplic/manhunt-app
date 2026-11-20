/** Snake_case shapes matching the FastAPI JSON wire format. */

export type LatLon = {
  lat: number
  lon: number
}

export type ArenaZoneKind = 'safe' | 'out_of_bounds' | 'seeker_spawn'

export type ArenaZoneShape =
  | { type: 'circle'; center: LatLon; radius_m: number }
  | { type: 'polygon'; vertices: LatLon[] }

export type ArenaZone = {
  id: string
  name: string
  kind: ArenaZoneKind
  shape: ArenaZoneShape
}

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
  boundary: LatLon[]
  boundary_circle?: {
    center: LatLon
    radius_m: number
  } | null
  zones: ArenaZone[]
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

export type RevealPin = {
  reveal_id: string
  player_id: string
  lat: number
  lon: number
  radius_m: number
  expires_in_s: number
  display_name: string
}

export type Banner = {
  banner_id: string
  tone: string
  title: string
  detail: string
  player_id: string | null
}

export type ViewTimers = {
  head_start_s?: number
  time_limit_s?: number
  reveal_interval_s?: number | null
  next_reveal_in_s?: number | null
  zone?: {
    radius_m: number
    next_radius_m: number
    shrinks_in_s: number
    interval_s: number
  } | null
}

/** Player view fields the web client consumes. */
export type PlayerView = {
  game_id: string
  join_code: string
  phase: string
  /** Seconds left in head_start (or null outside that phase). */
  phase_remaining_s?: number | null
  /** Seconds left on the hunt clock. */
  time_limit_remaining_s?: number | null
  game_elapsed_s?: number
  timers?: ViewTimers
  seeker_lock?: string | null
  spawn_lock?: {
    outside?: boolean
    holding?: boolean
    zones?: ArenaZone[]
  } | null
  you: {
    player_id: string
    role: string
    status: string
    is_host: boolean
    points?: number
    points_earned?: number
    hint?: string | null
    effects?: string[]
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
    points?: number
    points_earned?: number
    location?: {
      lat: number
      lon: number
      accuracy_m: number
      at: string
      kind: string
    } | null
  }>
  reveals?: RevealPin[]
  banners?: Banner[]
  arena?: {
    name?: string
    boundary?: LatLon[]
    boundary_circle?: {
      center: LatLon
      radius_m: number
    } | null
    zones?: ArenaZone[]
  } | null
  result?: GameResult | null
}
