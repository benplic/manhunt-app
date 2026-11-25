/**
 * Play circle radius limits. Keep in sync with the server (`PLAY_CIRCLE_MIN_M` and
 * `PLAY_CIRCLE_MAX_M` in `server/app/engine/arena.py`) and the iOS `ArenaValidator`.
 */
export const MIN_ARENA_RADIUS_M = 30
export const MAX_ARENA_RADIUS_M = 3000

export const ARENA_RADIUS_RANGE_MESSAGE = 'Radius must be between 30 m and 3,000 m.'

/** True for a finite number inside the allowed range, bounds included. */
export function isValidArenaRadius(radiusM: number): boolean {
  return (
    Number.isFinite(radiusM) && radiusM >= MIN_ARENA_RADIUS_M && radiusM <= MAX_ARENA_RADIUS_M
  )
}

/** A user-facing message for a bad radius, or null when it is fine to send. */
export function arenaRadiusError(radiusM: number): string | null {
  return isValidArenaRadius(radiusM) ? null : ARENA_RADIUS_RANGE_MESSAGE
}
