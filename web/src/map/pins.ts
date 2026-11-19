import type { PlayerView } from '../api/types'

export type MapPin = {
  playerId: string
  displayName: string
  role: string
  lat: number
  lon: number
  isYou: boolean
}

/** Pins from whatever locations the server already chose to reveal. */
export function pinsFromView(view: PlayerView): MapPin[] {
  return view.players.flatMap((player) => {
    const loc = player.location
    if (!loc) {
      return []
    }
    return [
      {
        playerId: player.player_id,
        displayName: player.display_name,
        role: player.role,
        lat: loc.lat,
        lon: loc.lon,
        isYou: player.player_id === view.you.player_id,
      },
    ]
  })
}
