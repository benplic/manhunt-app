import type { PlayerView, RevealPin } from '../api/types'

/** Reveal circles the server already chose for this viewer. */
export function revealsFromView(view: PlayerView): RevealPin[] {
  return (view.reveals ?? []).filter((pin) => pin.expires_in_s > 0)
}
