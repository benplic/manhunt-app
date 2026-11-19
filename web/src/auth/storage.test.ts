import { beforeEach, describe, expect, it } from 'vitest'
import {
  clearSession,
  getOrCreateInstallationId,
  loadHomeKey,
  loadSession,
  saveHomeKey,
  saveSession,
} from './storage'

describe('auth storage', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('persists access, refresh, and display name', () => {
    saveSession({
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      displayName: 'Casey',
      userId: 'user-1',
    })
    expect(loadSession()).toEqual({
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      displayName: 'Casey',
      userId: 'user-1',
    })
  })

  it('returns a stable installation id across calls', () => {
    const first = getOrCreateInstallationId()
    const second = getOrCreateInstallationId()
    expect(first.length).toBeGreaterThanOrEqual(8)
    expect(second).toBe(first)
  })

  it('stores the home key separately', () => {
    saveHomeKey('party-secret')
    expect(loadHomeKey()).toBe('party-secret')
  })

  it('clears session tokens but keeps installation id and home key', () => {
    saveSession({
      accessToken: 'a',
      refreshToken: 'r',
      displayName: 'Casey',
      userId: 'u',
    })
    const installId = getOrCreateInstallationId()
    saveHomeKey('party-secret')
    clearSession()
    expect(loadSession()).toBeNull()
    expect(getOrCreateInstallationId()).toBe(installId)
    expect(loadHomeKey()).toBe('party-secret')
  })
})
