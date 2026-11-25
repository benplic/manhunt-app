/**
 * Avatar color and ring assignment. Two players with the same initials must not look alike.
 *
 * Rule (identical on iOS, see ios/Manhunt/Domain/AvatarStyle.swift):
 *  1. Sort the roster by lowercase player id. That order is stable for the whole game.
 *  2. Each player prefers palette slot `djb2(id) % palette.length`.
 *  3. If a player with the same initials already holds that slot, take the next free slot.
 *  4. The nth player with the same initials gets ring cue `n % 4`, so color-blind players
 *     still have a shape difference. Players with unique initials get no ring.
 *
 * TODO: profile photos. Needs upload, storage, moderation, and PII decisions first.
 * Do not add uploads here until those are made.
 */

/** Dark text on every fill. Contrast against this is asserted in avatarStyle.test.ts. */
export const AVATAR_TEXT = '#111613'

/** Team colors from the iOS theme. Fills must stay visibly different from these. */
export const TEAM_COLORS = { seeker: '#E65440', hider: '#38BD85' } as const

export const AVATAR_PALETTE: readonly string[] = [
  '#F2DB47',
  '#F29E29',
  '#4FC3D9',
  '#A07BEF',
  '#EE82BC',
  '#5C8FF2',
  '#B8D95A',
  '#D6A67E',
  '#A9B6FF',
  '#F2B8A0',
  '#7FE0C8',
  '#D58AF0',
]

export const RING_CUE_COUNT = 4

export type AvatarStyle = {
  colorIndex: number
  color: string
  /** 0 = no ring, 1 = solid, 2 = dashed, 3 = dotted. */
  cue: number
}

export type AvatarPlayer = { id: string; name: string }

function firstGrapheme(text: string): string {
  if (typeof Intl !== 'undefined' && 'Segmenter' in Intl) {
    const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
    for (const part of segmenter.segment(text)) {
      return part.segment
    }
  }
  return Array.from(text)[0] ?? ''
}

/** First letter of the first two words, uppercased. "?" for an empty name. */
export function initialsFor(name: string): string {
  const words = name.split(/\s+/).filter((word) => word.length > 0)
  const letters = words.slice(0, 2).map(firstGrapheme)
  const joined = letters.join('').toUpperCase()
  return joined === '' ? '?' : joined
}

/** djb2 over UTF-8 bytes in 32-bit arithmetic. Swift mirrors it with &* and &+ on UInt32. */
export function idHash(id: string): number {
  let hash = 5381
  for (const byte of new TextEncoder().encode(id)) {
    hash = (Math.imul(hash, 33) + byte) >>> 0
  }
  return hash
}

export function assignAvatarStyles(
  players: readonly AvatarPlayer[],
  palette: readonly string[] = AVATAR_PALETTE,
): Map<string, AvatarStyle> {
  const sorted = [...players].sort((a, b) => {
    const left = a.id.toLowerCase()
    const right = b.id.toLowerCase()
    return left < right ? -1 : left > right ? 1 : 0
  })
  const takenByInitials = new Map<string, Set<number>>()
  const countByInitials = new Map<string, number>()
  const result = new Map<string, AvatarStyle>()
  for (const player of sorted) {
    const initials = initialsFor(player.name)
    const taken = takenByInitials.get(initials) ?? new Set<number>()
    // Count players, not distinct colors: once the palette is used up `taken` stops growing.
    const seen = countByInitials.get(initials) ?? 0
    const preferred = idHash(player.id.toLowerCase()) % palette.length
    // If every slot is taken (more same-initial players than colors) the duplicate is
    // unavoidable, so fall back to the preferred slot and let the ring cue tell them apart.
    let colorIndex = preferred
    for (let step = 0; step < palette.length; step += 1) {
      const candidate = (preferred + step) % palette.length
      if (!taken.has(candidate)) {
        colorIndex = candidate
        break
      }
    }
    result.set(player.id, {
      colorIndex,
      color: palette[colorIndex],
      cue: seen % RING_CUE_COUNT,
    })
    taken.add(colorIndex)
    countByInitials.set(initials, seen + 1)
    takenByInitials.set(initials, taken)
  }
  return result
}

function channel(value: number): number {
  const v = value / 255
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
}

function luminance(hex: string): number {
  const n = Number.parseInt(hex.slice(1), 16)
  return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255)
}

/** WCAG 2.x contrast ratio between two #RRGGBB colors. */
export function contrastRatio(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

export function colorDistance(a: string, b: string): number {
  const x = Number.parseInt(a.slice(1), 16)
  const y = Number.parseInt(b.slice(1), 16)
  const dr = ((x >> 16) & 255) - ((y >> 16) & 255)
  const dg = ((x >> 8) & 255) - ((y >> 8) & 255)
  const db = (x & 255) - (y & 255)
  return Math.sqrt(dr * dr + dg * dg + db * db)
}
