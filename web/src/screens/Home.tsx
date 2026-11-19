import { useState } from 'react'
import type { FormEvent } from 'react'
import { ApiError } from '../api/client'
import { createGame, joinGame } from '../api/games'
import type { PlayerView } from '../api/types'
import { clearSession, loadSession } from '../auth/storage'
import './Home.css'

type Props = {
  onSignedOut: () => void
  onEnteredGame: (view: PlayerView) => void
}

function readGps(): Promise<{ lat: number; lon: number }> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('Geolocation is not available in this browser.'))
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        resolve({ lat: pos.coords.latitude, lon: pos.coords.longitude })
      },
      () => {
        reject(new Error('Location permission is required to create a game.'))
      },
      { enableHighAccuracy: true, timeout: 15000 },
    )
  })
}

export function Home({ onSignedOut, onEnteredGame }: Props) {
  const session = loadSession()
  const [joinCode, setJoinCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [lastView, setLastView] = useState<PlayerView | null>(null)

  async function onCreate() {
    setError(null)
    if (!session) {
      onSignedOut()
      return
    }
    setBusy(true)
    try {
      const { lat, lon } = await readGps()
      const view = await createGame({ token: session.accessToken, lat, lon })
      setLastView(view)
      onEnteredGame(view)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  async function onJoin(event: FormEvent) {
    event.preventDefault()
    setError(null)
    if (!session) {
      onSignedOut()
      return
    }
    setBusy(true)
    try {
      const view = await joinGame({
        token: session.accessToken,
        joinCode: joinCode.trim(),
      })
      setLastView(view)
      onEnteredGame(view)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  function signOut() {
    clearSession()
    onSignedOut()
  }

  return (
    <main className="home">
      <header>
        <h1>Manhunt</h1>
        <p>Signed in as {session?.displayName ?? 'player'}</p>
      </header>

      <section>
        <h2>Create</h2>
        <p className="hint">Drops a 400 m circle on your current location. Keep the tab open for GPS.</p>
        <button type="button" onClick={onCreate} disabled={busy}>
          Create game
        </button>
      </section>

      <section>
        <h2>Join</h2>
        <form onSubmit={onJoin}>
          <label>
            Join code
            <input
              name="joinCode"
              value={joinCode}
              onChange={(e) => setJoinCode(e.target.value.toUpperCase())}
              autoCapitalize="characters"
              maxLength={8}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            Join
          </button>
        </form>
      </section>

      {error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : null}

      {lastView ? (
        <p className="status" role="status">
          In lobby · code {lastView.join_code} · phase {lastView.phase}
        </p>
      ) : null}

      <button type="button" className="linkish" onClick={signOut}>
        Sign out
      </button>
    </main>
  )
}
