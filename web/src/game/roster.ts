/**
 * Leaderboard grouping: Seekers, Hiders, and (lobby only) Unassigned sections.
 * Rank is overall and survives grouping, so a hider ranked 2nd still shows "2".
 * Roles are already sent to every viewer in the roster rows, so this widens nothing.
 * Mirror: ios/Manhunt/Domain/RosterGrouping.swift.
 */

export type RosterPlayer = {
  player_id: string
  display_name: string
  role: string
  status: string
  points?: number
  points_earned?: number
  converted_from_hider?: boolean
}

export type RosterSectionId = 'seekers' | 'hiders' | 'unassigned'

export type RosterRow<T extends RosterPlayer> = {
  player: T
  rank: number
  points: number
  /** A hider who was tagged and now hunts. Shown with a small "tagged" marker. */
  tagged: boolean
}

export type RosterSection<T extends RosterPlayer> = {
  id: RosterSectionId
  title: string
  rows: RosterRow<T>[]
}

export function playerPoints(player: RosterPlayer): number {
  return player.points_earned ?? player.points ?? 0
}

const SECTION_TITLES: Record<RosterSectionId, string> = {
  seekers: 'Seekers',
  hiders: 'Hiders',
  unassigned: 'Not on a team yet',
}

function sectionFor(role: string): RosterSectionId {
  if (role === 'seeker') {
    return 'seekers'
  }
  if (role === 'hider') {
    return 'hiders'
  }
  return 'unassigned'
}

/**
 * Competition ranking: equal points share a rank and the next rank skips ("1, 1, 3"),
 * so two players tied for first are not told one of them is second.
 */
export function rankPlayers<T extends RosterPlayer>(players: readonly T[]): RosterRow<T>[] {
  const sorted = [...players].sort((a, b) => {
    const diff = playerPoints(b) - playerPoints(a)
    if (diff !== 0) {
      return diff
    }
    // Stable, explicit tie-break so rows do not shuffle between renders.
    return a.player_id < b.player_id ? -1 : a.player_id > b.player_id ? 1 : 0
  })
  const rows: RosterRow<T>[] = []
  sorted.forEach((player, index) => {
    const points = playerPoints(player)
    const previous = rows[index - 1]
    rows.push({
      player,
      points,
      rank: previous && previous.points === points ? previous.rank : index + 1,
      tagged: Boolean(player.converted_from_hider) && player.role === 'seeker',
    })
  })
  return rows
}

/** Empty sections are dropped, so a lobby with no unassigned players shows two headers. */
export function groupRoster<T extends RosterPlayer>(players: readonly T[]): RosterSection<T>[] {
  const buckets: Record<RosterSectionId, RosterRow<T>[]> = {
    seekers: [],
    hiders: [],
    unassigned: [],
  }
  for (const row of rankPlayers(players)) {
    buckets[sectionFor(row.player.role)].push(row)
  }
  const order: RosterSectionId[] = ['seekers', 'hiders', 'unassigned']
  return order
    .filter((id) => buckets[id].length > 0)
    .map((id) => ({ id, title: SECTION_TITLES[id], rows: buckets[id] }))
}

export function statusNote(status: string): string {
  if (status === 'eliminated') {
    return 'out'
  }
  if (status === 'signal_lost') {
    return 'dark'
  }
  return ''
}
