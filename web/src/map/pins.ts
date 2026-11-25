import type { PlayerView } from '../api/types'
import { pingIntervalFromTimers } from '../game/fixFreshness'
import { pinOpacity } from './pinStaleness'
import { displayNameFor } from '../social/blockList'

export type MapPin = {
  playerId: string
  displayName: string
  role: string
  status: string
  lat: number
  lon: number
  isYou: boolean
  /** Wall-clock freshness paired with fix bars (1 = fresh, lower = older). */
  opacity: number
}

/** Pins from whatever locations the server already chose to reveal. */
export function pinsFromView(view: PlayerView, nowMs: number = Date.now()): MapPin[] {
  const viewerOut = view.you.status === 'eliminated'
  const pingIntervalS = pingIntervalFromTimers(view.timers)
  return (view.players ?? []).flatMap((player) => {
    if (viewerOut && player.player_id !== view.you.player_id) {
      return []
    }
    const loc = player.location
    if (!loc) {
      return []
    }
    const fixAtMs = Date.parse(loc.at)
    return [
      {
        playerId: player.player_id,
        displayName: displayNameFor(player.player_id, player.display_name),
        role: player.role,
        status: player.status,
        lat: loc.lat,
        lon: loc.lon,
        isYou: player.player_id === view.you.player_id,
        opacity: pinOpacity({
          fixAtMs: Number.isNaN(fixAtMs) ? null : fixAtMs,
          fixKind: loc.kind,
          status: player.status,
          pingIntervalS,
          nowMs,
        }),
      },
    ]
  })
}