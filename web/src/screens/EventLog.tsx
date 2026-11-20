import { useEffect, useState } from 'react'
import { ApiError } from '../api/client'
import { fetchGameEvents } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { TimelineEvent } from '../api/types'
import './EventLog.css'

type Props = {
  gameId: string
  onClose: () => void
  onSignedOut: () => void
}

function eventText(event: TimelineEvent): string {
  const text = event.payload?.text
  if (typeof text === 'string' && text.length > 0) {
    return text
  }
  return event.type
}

export function EventLog({ gameId, onClose, onSignedOut }: Props) {
  const [events, setEvents] = useState<TimelineEvent[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    void withAuthRetry((token) => fetchGameEvents({ token, gameId }))
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
          return
        }
        setError(err instanceof ApiError ? err.message : (err as Error).message)
      })
    return () => {
      cancelled = true
    }
  }, [gameId, onSignedOut])

  return (
    <main className="event-log">
      <header>
        <h1>Event log</h1>
        <button type="button" className="chip" onClick={onClose}>
          Close
        </button>
      </header>
      {error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : null}
      {events === null ? <p>Loading…</p> : null}
      {events && events.length === 0 ? <p className="empty">No events yet.</p> : null}
      {events && events.length > 0 ? (
        <ol>
          {events.map((event) => (
            <li key={event.seq}>
              <span className="seq">{event.seq}</span>
              <span className="type">{event.type}</span>
              <span className="detail">{eventText(event)}</span>
            </li>
          ))}
        </ol>
      ) : null}
    </main>
  )
}