import { beforeEach, describe, expect, it, vi } from 'vitest'
import { signInDev, TooYoungError } from './auth'

describe('signInDev', () => {
  beforeEach(() => {
    localStorage.clear()
    vi.unstubAllGlobals()
  })

  it('rejects ages under 13 before calling the network', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    await expect(
      signInDev({
        displayName: 'Kid',
        age: 12,
        homeKey: 'secret',
      }),
    ).rejects.toBeInstanceOf(TooYoungError)

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('POSTs snake_case body and home-key header to /v1/auth/dev', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        access_token: 'tok',
        expires_at: '2099-01-01T00:00:00+00:00',
        user: { id: 'u1', display_name: 'Casey', avatar_url: null },
        refresh_token: 'ref',
      }),
    })
    vi.stubGlobal('fetch', fetchMock)

    const auth = await signInDev({
      displayName: 'Casey',
      age: 18,
      homeKey: 'party-secret',
      installationId: 'install-abc-12345',
    })

    expect(auth.access_token).toBe('tok')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/v1\/auth\/dev$/)
    expect(init.method).toBe('POST')
    expect(init.headers['X-Manhunt-Dev-Secret']).toBe('party-secret')
    expect(init.headers['Content-Type']).toBe('application/json')
    expect(JSON.parse(init.body)).toEqual({
      display_name: 'Casey',
      installation_id: 'install-abc-12345',
      age: 18,
    })
  })

  it('persists tokens and home key after a successful sign-in', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({
          access_token: 'tok',
          expires_at: '2099-01-01T00:00:00+00:00',
          user: { id: 'u1', display_name: 'Casey', avatar_url: null },
          refresh_token: 'ref',
        }),
      }),
    )

    await signInDev({
      displayName: 'Casey',
      age: 18,
      homeKey: 'party-secret',
      installationId: 'install-abc-12345',
    })

    expect(localStorage.getItem('manhunt.accessToken')).toBe('tok')
    expect(localStorage.getItem('manhunt.refreshToken')).toBe('ref')
    expect(localStorage.getItem('manhunt.homeKey')).toBe('party-secret')
    expect(localStorage.getItem('manhunt.displayName')).toBe('Casey')
    expect(localStorage.getItem('manhunt.userId')).toBe('u1')
  })
})
