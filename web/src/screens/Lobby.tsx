import { useEffect, useMemo, useState } from 'react'
import QRCode from 'qrcode'
import { ApiError } from '../api/client'
import {
  DEFAULT_ARENA_RADIUS_M,
  randomizeRoles,
  setLobbyCircle,
  setManualRoles,
  startGame,
} from '../api/games'
import { joinUrlForCode } from '../api/joinCode'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { PlayerView } from '../api/types'
import './Lobby.css'

type Props = {
  view: PlayerView
  onView: (view: PlayerView) => void
  onLeave: () => void
  onSignedOut: () => void
  socketNote?: string | null
}

type RoleChoice = 'seeker' | 'hider'

function rolesReady(view: PlayerView): boolean {
  const seekers = view.players.filter((p) => p.role === 'seeker')
  const hiders = view.players.filter((p) => p.role === 'hider')
  return seekers.length >= 1 && hiders.length >= 1
}

export function Lobby({ view, onView, onLeave, onSignedOut, socketNote }: Props) {
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [joinQr, setJoinQr] = useState<string | null>(null)
  const radiusNow = view.arena?.boundary_circle?.radius_m ?? DEFAULT_ARENA_RADIUS_M
  const [radiusDraft, setRadiusDraft] = useState(radiusNow)
  const isHost = view.you.is_host
  const alert = error ?? socketNote ?? null
  const canStart = rolesReady(view) && view.players.length >= 2

  const joinLink = useMemo(() => joinUrlForCode(view.join_code), [view.join_code])

  useEffect(() => {
    setRadiusDraft(radiusNow)
  }, [radiusNow])

  useEffect(() => {
    let cancelled = false
    QRCode.toDataURL(joinLink, { width: 220, margin: 1 })
      .then((url) => {
        if (!cancelled) {
          setJoinQr(url)
        }
      })
      .catch(() => {
        if (!cancelled) {
          setJoinQr(null)
        }
      })
    return () => {
      cancelled = true
    }
  }, [joinLink])

  function handleAuth(err: unknown): boolean {
    if (err instanceof SessionExpiredError) {
      onSignedOut()
      return true
    }
    return false
  }

  async function onRandomize() {
    setError(null)
    setBusy(true)
    try {
      const next = await withAuthRetry((token) =>
        randomizeRoles({ token, gameId: view.game_id, seekerCount: 1 }),
      )
      onView(next)
    } catch (err) {
      if (handleAuth(err)) {
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  async function onToggleRole(playerId: string, role: RoleChoice) {
    setError(null)
    setBusy(true)
    try {
      const assignments: Record<string, RoleChoice> = {}
      for (const player of view.players) {
        assignments[player.player_id] =
          player.player_id === playerId
            ? role
            : player.role === 'seeker' || player.role === 'hider'
              ? player.role
              : 'hider'
      }
      // Ensure the toggled seat wins even if they were unassigned.
      assignments[playerId] = role
      const next = await withAuthRetry((token) =>
        setManualRoles({ token, gameId: view.game_id, assignments }),
      )
      onView(next)
    } catch (err) {
      if (handleAuth(err)) {
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  async function onApplyRadius() {
    setError(null)
    setBusy(true)
    try {
      const next = await withAuthRetry((token) =>
        setLobbyCircle({ token, gameId: view.game_id, radiusM: radiusDraft }),
      )
      onView(next)
    } catch (err) {
      if (handleAuth(err)) {
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  async function onStart() {
    setError(null)
    setBusy(true)
    try {
      if (!rolesReady(view)) {
        await withAuthRetry((token) =>
          randomizeRoles({ token, gameId: view.game_id, seekerCount: 1 }),
        )
      }
      const started = await withAuthRetry((token) =>
        startGame({ token, gameId: view.game_id }),
      )
      onView(started)
    } catch (err) {
      if (handleAuth(err)) {
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

      <section className="join-qr">
        <h2>Join QR</h2>
        {joinQr ? (
          <img src={joinQr} alt={`Join QR for ${view.join_code}`} width={220} height={220} />
        ) : (
          <p className="hint">Drawing join code…</p>
        )}
        <p className="hint">Friends can Scan on the home screen instead of typing the code.</p>
      </section>

      <section>
        <h2>Players</h2>
        <ul>
          {view.players.map((player) => (
            <li key={player.player_id}>
              <div>
                <span>{player.display_name}</span>
                <span className="meta">
                  {player.role}
                  {player.is_host ? ' · host' : ''}
                </span>
              </div>
              {isHost ? (
                <div className="role-toggles">
                  <button
                    type="button"
                    className={player.role === 'seeker' ? 'active' : undefined}
                    disabled={busy}
                    onClick={() => void onToggleRole(player.player_id, 'seeker')}
                  >
                    Seeker
                  </button>
                  <button
                    type="button"
                    className={player.role === 'hider' ? 'active' : undefined}
                    disabled={busy}
                    onClick={() => void onToggleRole(player.player_id, 'hider')}
                  >
                    Hider
                  </button>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
        {isHost ? (
          <button type="button" className="secondary" disabled={busy} onClick={() => void onRandomize()}>
            Randomize roles
          </button>
        ) : null}
      </section>

      {isHost ? (
        <section>
          <h2>Play circle</h2>
          <p className="hint">
            Current radius {Math.round(radiusNow)} m. Guests outside this circle risk an
            out-of-bounds auto-tag.
          </p>
          <label>
            Radius (m)
            <input
              type="number"
              min={30}
              max={2000}
              step={50}
              value={radiusDraft}
              onChange={(e) => setRadiusDraft(Number(e.target.value))}
            />
          </label>
          <button
            type="button"
            className="secondary"
            disabled={busy || radiusDraft === radiusNow}
            onClick={() => void onApplyRadius()}
          >
            Apply radius
          </button>
        </section>
      ) : (
        <p className="hint">Play circle: {Math.round(radiusNow)} m</p>
      )}

      {isHost ? (
        <button type="button" onClick={() => void onStart()} disabled={busy || view.players.length < 2}>
          {busy ? 'Starting…' : 'Start'}
        </button>
      ) : (
        <p className="waiting">Waiting for host to start…</p>
      )}

      {view.players.length < 2 && isHost ? (
        <p className="hint">Need at least one guest before start.</p>
      ) : null}
      {isHost && view.players.length >= 2 && !canStart ? (
        <p className="hint">Assign at least one seeker and one hider (or tap Randomize).</p>
      ) : null}

      {alert ? (
        <p className="error" role="alert">
          {alert}
        </p>
      ) : null}

      <button type="button" className="linkish" onClick={onLeave}>
        Leave
      </button>
    </main>
  )
}
