import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from './client'
import { withAuthRetry, SessionExpiredError } from './session'

const refreshAccessToken = vi.fn()

vi.mock('./auth', () => ({
  refreshAccessToken: (...args: unknown[]) => refreshAccessToken(...args),
}))

describe('withAuthRetry', () => {
  beforeEach(() => {
    localStorage.clear()
    refreshAccessToken.mockReset()
    localStorage.setItem('manhunt.accessToken', 'old-tok')
    localStorage.setItem('manhunt.refreshToken', 'ref-tok')
    localStorage.setItem('manhunt.displayName', 'Casey')
    localStorage.setItem('manhunt.userId', 'u1')
  })

  it('retries once after refreshing on TOKEN_EXPIRED', async () => {
    const call = vi
      .fn()
      .mockRejectedValueOnce(new ApiError('TOKEN_EXPIRED', 'expired', 401))
      .mockResolvedValueOnce('ok')
    refreshAccessToken.mockResolvedValue({
      access_token: 'new-tok',
      expires_at: '2099-01-01T00:00:00+00:00',
      user: { id: 'u1', display_name: 'Casey', avatar_url: null },
      refresh_token: 'ref-2',
    })

    await expect(withAuthRetry((token) => call(token))).resolves.toBe('ok')
    expect(refreshAccessToken).toHaveBeenCalledWith('ref-tok')
    expect(call).toHaveBeenNthCalledWith(1, 'old-tok')
    expect(call).toHaveBeenNthCalledWith(2, 'new-tok')
  })

  it('clears the session and throws SessionExpiredError when refresh fails', async () => {
    const call = vi.fn().mockRejectedValue(new ApiError('TOKEN_INVALID', 'bad', 401))
    refreshAccessToken.mockRejectedValue(new ApiError('TOKEN_INVALID', 'bad refresh', 401))

    await expect(withAuthRetry((token) => call(token))).rejects.toBeInstanceOf(
      SessionExpiredError,
    )
    expect(localStorage.getItem('manhunt.accessToken')).toBeNull()
  })
})
