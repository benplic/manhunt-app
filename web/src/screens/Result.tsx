import { useState } from 'react'
import { ApiError } from '../api/client'
import { rematchGame } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { PlayerView } from '../api/types'
import './Result.css'

type Props = {
  view: PlayerView
  onDone: () => void
  onRematch: (view: PlayerView) => void
  onSignedOut: () => void
}

function winnerCopy(winner: string): string {
  if (winner === 'hiders') {
    return 'HIDERS WIN'
  }
  if (winner === 'seekers') {
    return 'SEEKERS WIN'
  }
  return 'HUNT OVER'
}

export function Result({ view, onDone, onRematch, onSignedOut }: Props) {
  const result = view.result
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function onRematchClick() {
    setBusy(true)
    setError(null)
    try {
      const next = await withAuthRetry((token) =>
        rematchGame({ token, gameId: view.game_id }),
      )
      onRematch(next)
    } catch (err) {
      if (err instanceof SessionExpiredError) {
        onSignedOut()
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const ranked = [...view.players].sort(
    (a, b) => (b.points_earned ?? b.points ?? 0) - (a.points_earned ?? a.points ?? 0),
  )

  return (
    <main className="result">
      <h1>{result ? winnerCopy(result.winner) : 'Hunt over'}</h1>
      {result ? <p className="reason">{result.reason}</p> : <p>No result payload from the server.</p>}
      <p className="code">Code was {view.join_code}</p>
      {error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : null}
      <div className="actions">
        <button type="button" disabled={busy} onClick={() => void onRematchClick()}>
          {busy ? 'Rematching…' : 'Rematch'}
        </button>
        <button type="button" className="secondary" onClick={onDone}>
          Home
        </button>
      </div>
      {ranked.length > 0 ? (
        <section className="scores">
          <h2>Scores</h2>
          <ul>
            {ranked.map((player) => (
              <li key={player.player_id}>
                <strong>{player.display_name}</strong>
                <span>
                  {player.role} · {player.points_earned ?? player.points ?? 0} pts
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  )
}
