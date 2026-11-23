import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { ApiError } from '../api/client'
import { createGame, DEFAULT_ARENA_RADIUS_M, joinGame } from '../api/games'
import { parseJoinPayload, sanitizeJoinCode } from '../api/joinCode'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { PlayerView } from '../api/types'
import { clearSession, loadSession } from '../auth/storage'
import { Account } from './Account'
import { JoinScan } from './JoinScan'
import './Home.css'

type Props = {
  onSignedOut: () => void
  onEnteredGame: (view: PlayerView) => void
  /** Shown after a failed or cancelled rejoin (closed hunt, etc.). */
  bannerNote?: string | null
  onClearBanner?: () => void
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
      // maximumAge: 0 forces a fresh fix so the circle lands on the host now.
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    )
  })
}

function joinFromLocation(): string {
  try {
    return parseJoinPayload(window.location.href)
  } catch {
    return ''
  }
}

export function Home({ onSignedOut, onEnteredGame, bannerNote = null, onClearBanner }: Props) {
  const session = loadSession()
  const [joinCode, setJoinCode] = useState(() => joinFromLocation())
  const [radiusM, setRadiusM] = useState(DEFAULT_ARENA_RADIUS_M)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [scanning, setScanning] = useState(false)
  const [accountOpen, setAccountOpen] = useState(false)
  const alert = error ?? bannerNote

  useEffect(() => {
    const fromUrl = joinFromLocation()
    if (fromUrl) {
      setJoinCode(fromUrl)
      // Drop the invite from the address bar so a refresh does not look like a new join.
      const url = new URL(window.location.href)
      let changed = false
      if (url.searchParams.has('join')) {
        url.searchParams.delete('join')
        changed = true
      }
      if (/^\/join\/[^/]+\/?$/i.test(url.pathname)) {
        url.pathname = '/'
        changed = true
      }
      if (changed) {
        window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`)
      }
    }
  }, [])

  function handleAuthFailure(err: unknown): boolean {
    if (err instanceof SessionExpiredError) {
      onSignedOut()
      return true
    }
    return false
  }

  async function onCreate() {
    setError(null)
    if (!session) {
      onSignedOut()
      return
    }
    setBusy(true)
    try {
      const { lat, lon } = await readGps()
      const view = await withAuthRetry((token) =>
        createGame({ token, lat, lon, radiusM }),
      )
      onEnteredGame(view)
    } catch (err) {
      if (handleAuthFailure(err)) {
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  async function joinWithCode(codeRaw: string) {
    setError(null)
    if (!session) {
      onSignedOut()
      return
    }
    const code = sanitizeJoinCode(codeRaw)
    if (code.length !== 6) {
      setError('Join codes are 6 characters.')
      return
    }
    setBusy(true)
    try {
      const view = await withAuthRetry((token) => joinGame({ token, joinCode: code }))
      onEnteredGame(view)
    } catch (err) {
      if (handleAuthFailure(err)) {
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  async function onJoin(event: FormEvent) {
    event.preventDefault()
    await joinWithCode(joinCode)
  }

  function signOut() {
    clearSession()
    onSignedOut()
  }

  if (accountOpen) {
    return (
      <Account onClose={() => setAccountOpen(false)} onSignedOut={onSignedOut} />
    )
  }

  if (scanning) {
    return (
      <JoinScan
        onClose={() => setScanning(false)}
        onCode={(code) => {
          setScanning(false)
          setJoinCode(code)
          void joinWithCode(code)
        }}
      />
    )
  }

  return (
    <main className="home">
      <header>
        <h1>Manhunt</h1>
        <p>Signed in as {session?.displayName ?? 'player'}</p>
        <div className="home-actions">
          <button type="button" className="secondary" onClick={() => setAccountOpen(true)}>
            Account
          </button>
        </div>
      </header>

      <section>
        <h2>Create</h2>
        <label>
          Play circle radius (m)
          <input
            type="number"
            min={30}
            max={2000}
            step={50}
            value={radiusM}
            onChange={(e) => setRadiusM(Number(e.target.value))}
          />
        </label>
        <p className="hint">
          Centers a {radiusM} m circle on your GPS. You can change it again in the lobby.
        </p>
        <button type="button" onClick={() => void onCreate()} disabled={busy}>
          Create game
        </button>
      </section>

      <section>
        <h2>Join</h2>
        <form onSubmit={(e) => void onJoin(e)}>
          <label>
            Join code
            <input
              name="joinCode"
              value={joinCode}
              onChange={(e) => setJoinCode(sanitizeJoinCode(e.target.value))}
              autoCapitalize="characters"
              maxLength={6}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            Join
          </button>
        </form>
        <button type="button" className="secondary" disabled={busy} onClick={() => setScanning(true)}>
          Scan join QR
        </button>
      </section>

      {alert ? (
        <p className="error" role="alert">
          {alert}
          {bannerNote && !error && onClearBanner ? (
            <>
              {' '}
              <button type="button" className="linkish" onClick={onClearBanner}>
                Dismiss
              </button>
            </>
          ) : null}
        </p>
      ) : null}

      <button type="button" className="linkish" onClick={signOut}>
        Sign out
      </button>
    </main>
  )
}
