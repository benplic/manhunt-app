import { useEffect, useState } from 'react'
import { ApiError } from '../api/client'
import { fetchGameEvents, rematchGame } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { PlayerView, TimelineEvent } from '../api/types'
import { displayNameFor } from '../social/blockList'
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

function eventText(event: TimelineEvent): string {
  const text = event.payload?.text
  if (typeof text === 'string' && text.length > 0) {
    return text
  }
  return event.type
}

export function Result({ view, onDone, onRematch, onSignedOut }: Props) {
  const result = view.result
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [events, setEvents] = useState<TimelineEvent[] | null>(null)

  useEffect(() => {
    let cancelled = false
    void withAuthRetry((token) => fetchGameEvents({ token, gameId: view.game_id }))
      .then((payload) => {
        if (!cancelled) {
          setEvents(payload.events)
        }
      })
      .catch((err) => {
        if (cancelled) {
          return
        }
        if (err instanceof SessionExpiredError) {
          onSignedOut()
        }
      })
    return () => {
      cancelled = true
    }
  }, [view.game_id, onSignedOut])

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
                <strong>{displayNameFor(player.player_id, player.display_name)}</strong>
                <span>
                  {player.role} · {player.points_earned ?? player.points ?? 0} pts
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      {events && events.length > 0 ? (
        <details className="event-log-section">
          <summary>Event log ({events.length})</summary>
          <ol>
            {events.map((event) => (
              <li key={event.seq}>
                <span className="seq">{event.seq}</span>
                <span className="type">{event.type}</span>
                <span>{eventText(event)}</span>
              </li>
            ))}
          </ol>
        </details>
      ) : null}
    </main>
  )
}
