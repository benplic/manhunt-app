/** Remember the open game across a refresh so the socket can rejoin. */

const KEY = 'manhunt.activeGameId'

export function rememberActiveGame(gameId: string): void {
  sessionStorage.setItem(KEY, gameId)
}

export function clearActiveGame(): void {
  sessionStorage.removeItem(KEY)
}

export function loadActiveGameId(): string | null {
  return sessionStorage.getItem(KEY)
}
