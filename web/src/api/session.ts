import { clearSession, loadSession } from '../auth/storage'
import { refreshAccessToken } from './auth'
import { ApiError } from './client'

export class SessionExpiredError extends Error {
  constructor() {
    super('Your session expired. Sign in again.')
    this.name = 'SessionExpiredError'
  }
}

function isAuthFailure(err: unknown): boolean {
  if (!(err instanceof ApiError)) {
    return false
  }
  return (
    err.status === 401 ||
    err.code === 'TOKEN_EXPIRED' ||
    err.code === 'TOKEN_INVALID' ||
    err.code === 'UNAUTHORIZED'
  )
}

/**
 * Run an authed call with the stored access token. On 401/token errors,
 * rotate the refresh token once; if that fails, clear the session.
 */
export async function withAuthRetry<T>(fn: (accessToken: string) => Promise<T>): Promise<T> {
  const session = loadSession()
  if (!session) {
    throw new SessionExpiredError()
  }

  try {
    return await fn(session.accessToken)
  } catch (err) {
    if (!isAuthFailure(err) || !session.refreshToken) {
      throw err
    }
    try {
      const refreshed = await refreshAccessToken(session.refreshToken)
      return await fn(refreshed.access_token)
    } catch {
      clearSession()
      throw new SessionExpiredError()
    }
  }
}
