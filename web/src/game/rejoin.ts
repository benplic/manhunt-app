import { ApiError } from '../api/client'

/** Errors that mean the stored game id is no longer a live seat to resume. */
const CLOSED_CODES = new Set(['GAME_NOT_FOUND', 'NOT_A_MEMBER', 'WRONG_PHASE'])

/**
 * True when rejoin should stop and clear the remembered game id.
 * Covers deleted rows, removed seats, and abandoned / closed hunts.
 */
export function isClosedGameError(err: unknown): boolean {
  if (!(err instanceof ApiError)) {
    return false
  }
  if (CLOSED_CODES.has(err.code)) {
    return true
  }
  // Some proxies strip the body; treat plain 404 as gone.
  return err.status === 404
}

/** Short copy for the home banner after a failed rejoin. */
export function closedGameMessage(err: unknown): string {
  if (err instanceof ApiError) {
    if (err.code === 'NOT_A_MEMBER') {
      return 'You are no longer in that hunt. Start or join a new one.'
    }
    if (err.code === 'WRONG_PHASE') {
      return 'That hunt is closed. Start or join a new one.'
    }
    if (err.code === 'GAME_NOT_FOUND' || err.status === 404) {
      return 'That hunt is gone or already finished. Start or join a new one.'
    }
    return err.message
  }
  return 'Could not rejoin that hunt. Start or join a new one.'
}
