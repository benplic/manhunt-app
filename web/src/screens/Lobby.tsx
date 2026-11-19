import { useEffect, useState } from 'react'
import { ApiError } from '../api/client'
import { apiBaseUrl } from '../api/config'
import { randomizeRoles, startGame } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { PlayerView } from '../api/types'
import { GameSocket, wsUrlForGame } from '../api/ws'
import { loadSession } from '../auth/storage'
import './Lobby.css'

type Props = {
  view: PlayerView
  onView: (view: PlayerView) => void
  onLeave: () => void
  onSignedOut: () => void
  createSocket?: () => GameSocket
}

export function Lobby({
  view,
  onView,
  onLeave,
  onSignedOut,
  createSocket = () => new GameSocket(),
}: Props) {
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const isHost = view.you.is_host

  useEffect(() => {
    const session = loadSession()
    if (!session) {
      return
    }
    const socket = createSocket()
    socket.onView = (next) => onView(next)
    socket.onError = (err) => setError(err.message)
    socket.connect({
      url: wsUrlForGame(apiBaseUrl(), view.game_id),
      token: session.accessToken,
    })
    return () => socket.disconnect()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view.game_id])

  async function onStart() {
    setError(null)
    setBusy(true)
    try {
      // One seeker for the web MVP; roles must exist before start (NEED_BOTH_ROLES).
      await withAuthRetry((token) =>
        randomizeRoles({ token, gameId: view.game_id, seekerCount: 1 }),
      )
      const started = await withAuthRetry((token) =>
        startGame({ token, gameId: view.game_id }),
      )
      onView(started)
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

  return (
    <main className="lobby">
      <header>
        <h1>Lobby</h1>
        <p className="code">
          Join code <strong>{view.join_code}</strong>
        </p>
      </header>

      <section>
        <h2>Players</h2>
        <ul>
          {view.players.map((player) => (
            <li key={player.player_id}>
              <span>{player.display_name}</span>
              <span className="meta">
                {player.role}
                {player.is_host ? ' · host' : ''}
              </span>
            </li>
          ))}
        </ul>
      </section>

      {isHost ? (
        <button type="button" onClick={onStart} disabled={busy || view.players.length < 2}>
          {busy ? 'Starting…' : 'Start'}
        </button>
      ) : (
        <p className="waiting">Waiting for host to start…</p>
      )}

      {view.players.length < 2 && isHost ? (
        <p className="hint">Need at least one guest before start.</p>
      ) : null}

      {error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : null}

      <button type="button" className="linkish" onClick={onLeave}>
        Leave
      </button>
    </main>
  )
}
