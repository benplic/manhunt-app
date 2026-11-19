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

/** Build a scannable join link for the current Pages/local origin. */
export function joinUrlForCode(code: string, origin: string = window.location.origin): string {
  const cleaned = sanitizeJoinCode(code)
  return `${origin.replace(/\/$/, '')}/?join=${cleaned}`
}

/**
 * Pull a join code from typed text, a `?join=` URL, or a bare 6-character code.
 * Returns '' when nothing valid is present.
 */
export function parseJoinPayload(raw: string): string {
  const trimmed = raw.trim()
  if (!trimmed) {
    return ''
  }
  try {
    const url = new URL(trimmed)
    // Only trust an explicit ?join= on URLs. Never alphabet-strip the host.
    return sanitizeJoinCode(url.searchParams.get('join') ?? '')
  } catch {
    // Not a URL — bare code or QR payload.
  }
  return sanitizeJoinCode(trimmed)
}
