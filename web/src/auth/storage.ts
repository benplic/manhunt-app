/** localStorage keys for the web MVP session. Not for secrets beyond the party home key. */

const ACCESS = 'manhunt.accessToken'
const REFRESH = 'manhunt.refreshToken'
const DISPLAY = 'manhunt.displayName'
const USER = 'manhunt.userId'
const INSTALL = 'manhunt.installationId'
const HOME_KEY = 'manhunt.homeKey'

export type StoredSession = {
  accessToken: string
  refreshToken: string | null
  displayName: string
  userId: string
}

export function saveSession(session: StoredSession): void {
  localStorage.setItem(ACCESS, session.accessToken)
  if (session.refreshToken) {
    localStorage.setItem(REFRESH, session.refreshToken)
  } else {
    localStorage.removeItem(REFRESH)
  }
  localStorage.setItem(DISPLAY, session.displayName)
  localStorage.setItem(USER, session.userId)
}

export function loadSession(): StoredSession | null {
  const accessToken = localStorage.getItem(ACCESS)
  const displayName = localStorage.getItem(DISPLAY)
  const userId = localStorage.getItem(USER)
  if (!accessToken || !displayName || !userId) {
    return null
  }
  return {
    accessToken,
    refreshToken: localStorage.getItem(REFRESH),
    displayName,
    userId,
  }
}

export function clearSession(): void {
  localStorage.removeItem(ACCESS)
  localStorage.removeItem(REFRESH)
  localStorage.removeItem(DISPLAY)
  localStorage.removeItem(USER)
}

export function getOrCreateInstallationId(): string {
  const existing = localStorage.getItem(INSTALL)
  if (existing && existing.length >= 8) {
    return existing
  }
  const id =
    typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID()
      : `web-${Date.now()}-${Math.random().toString(36).slice(2)}`
  localStorage.setItem(INSTALL, id)
  return id
}

export function saveHomeKey(homeKey: string): void {
  localStorage.setItem(HOME_KEY, homeKey)
}

export function loadHomeKey(): string | null {
  return localStorage.getItem(HOME_KEY)
}
