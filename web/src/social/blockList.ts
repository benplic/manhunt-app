/**
 * Device-local blocked players. Same idea as iOS PlayerBlockList:
 * not synced to the server; anonymize names on this browser only.
 */

const ENTRIES_KEY = 'manhunt.blockedPlayerEntries'

export type BlockedPlayerEntry = {
  playerId: string
  displayName: string
}

function readEntries(): BlockedPlayerEntry[] {
  try {
    const raw = localStorage.getItem(ENTRIES_KEY)
    if (!raw) {
      return []
    }
    const parsed = JSON.parse(raw) as BlockedPlayerEntry[]
    if (!Array.isArray(parsed)) {
      return []
    }
    return parsed.filter(
      (row) =>
        row &&
        typeof row.playerId === 'string' &&
        typeof row.displayName === 'string' &&
        row.playerId.length > 0,
    )
  } catch {
    return []
  }
}

function writeEntries(next: BlockedPlayerEntry[]): void {
  localStorage.setItem(ENTRIES_KEY, JSON.stringify(next))
}

export function listBlockedPlayers(): BlockedPlayerEntry[] {
  return readEntries()
}

export function isBlocked(playerId: string): boolean {
  return readEntries().some((row) => row.playerId === playerId)
}

/** Stable public label: Blocked Player #1, #2, … by sorted id order. */
export function anonymizedName(playerId: string): string | null {
  const ordered = readEntries()
    .map((row) => row.playerId)
    .sort()
  const index = ordered.indexOf(playerId)
  if (index < 0) {
    return null
  }
  return `Blocked Player #${index + 1}`
}

export function displayNameFor(playerId: string, fallback: string): string {
  return anonymizedName(playerId) ?? fallback
}

export function blockPlayer(playerId: string, displayName: string): void {
  const trimmed = displayName.trim() || 'Player'
  const next = readEntries().filter((row) => row.playerId !== playerId)
  next.push({ playerId, displayName: trimmed })
  writeEntries(next)
}

export function unblockPlayer(playerId: string): void {
  writeEntries(readEntries().filter((row) => row.playerId !== playerId))
}

export function reportMailto(input: {
  gameId: string
  playerId: string
  displayName: string
  supportEmail: string
}): string {
  const body = [
    `game_id: ${input.gameId}`,
    `player_id: ${input.playerId}`,
    `display_name: ${input.displayName}`,
  ].join('\n')
  const params = new URLSearchParams({
    subject: 'Manhunt player report',
    body,
  })
  return `mailto:${input.supportEmail}?${params.toString()}`
}
