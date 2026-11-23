/** Matches server/app/games/join_code.py ALPHABET (no I/L/O/0/1). */
export const JOIN_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'

export function sanitizeJoinCode(raw: string): string {
  return raw
    .toUpperCase()
    .split('')
    .filter((ch) => JOIN_CODE_ALPHABET.includes(ch))
    .slice(0, 6)
    .join('')
}

/** Public site printed under an iOS lobby QR. Local web dev uses its own origin. */
export const PUBLIC_WEB_ORIGIN = 'https://manhunt-app.pages.dev'

/** Build a scannable join link. Path form matches the iOS lobby QR. */
export function joinUrlForCode(code: string, origin: string = window.location.origin): string {
  const cleaned = sanitizeJoinCode(code)
  return `${origin.replace(/\/$/, '')}/join/${cleaned}`
}

/**
 * Pull a join code from typed text, `/join/CODE`, `?join=CODE`, `manhunt://join/CODE`,
 * or a bare 6-character code. Returns '' when nothing valid is present.
 * Never alphabet-strip the hostname into a fake code.
 */
export function parseJoinPayload(raw: string): string {
  const trimmed = raw.trim()
  if (!trimmed) {
    return ''
  }
  try {
    const url = new URL(trimmed)
    const fromQuery = sanitizeJoinCode(url.searchParams.get('join') ?? '')
    if (fromQuery.length === 6) {
      return fromQuery
    }
    if (url.protocol === 'manhunt:' && url.hostname.toLowerCase() === 'join') {
      const custom = sanitizeJoinCode(url.pathname.replace(/^\//, ''))
      return custom.length === 6 ? custom : ''
    }
    const parts = url.pathname.split('/').filter(Boolean)
    const joinAt = parts.findIndex((part) => part.toLowerCase() === 'join')
    if (joinAt >= 0 && parts[joinAt + 1]) {
      const fromPath = sanitizeJoinCode(parts[joinAt + 1])
      return fromPath.length === 6 ? fromPath : ''
    }
    return ''
  } catch {
    // Not a URL — bare code or QR payload.
  }
  const bare = sanitizeJoinCode(trimmed)
  return bare.length === 6 ? bare : ''
}
