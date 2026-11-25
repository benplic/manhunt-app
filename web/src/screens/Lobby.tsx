import { useEffect, useMemo, useState } from 'react'
import QRCode from 'qrcode'
import { ApiError } from '../api/client'
import {
  DEFAULT_ARENA_RADIUS_M,
  randomizeRoles,
  removeLobbyPlayer,
  setLobbyCircle,
  setManualRoles,
  startGame,
} from '../api/games'
import { rulesSummaryLine } from '../game/rulesSummary'
import { joinUrlForCode } from '../api/joinCode'
import { SUPPORT_EMAIL } from '../api/legal'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { PlayerView } from '../api/types'
import { ConfirmDialog } from '../game/ConfirmDialog'
import { arenaRadiusError, MAX_ARENA_RADIUS_M, MIN_ARENA_RADIUS_M } from '../geo/arenaRadius'
import { blockPlayer, displayNameFor, reportMailto } from '../social/blockList'
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
  const [pendingLeave, setPendingLeave] = useState(false)
  const [pendingBlock, setPendingBlock] = useState<{ id: string; name: string } | null>(null)
  const [busy, setBusy] = useState(false)
  const [joinQr, setJoinQr] = useState<string | null>(null)
  const radiusNow = view.arena?.boundary_circle?.radius_m ?? DEFAULT_ARENA_RADIUS_M
  const [radiusDraft, setRadiusDraft] = useState(radiusNow)
  const radiusDraftError = arenaRadiusError(radiusDraft)
  const [note, setNote] = useState<string | null>(null)
  const isHost = view.you.is_host
  const alert = error ?? note ?? socketNote ?? null
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

  async function onRemovePlayer(playerId: string, displayName: string) {
    if (!window.confirm(`Remove ${displayName} from the lobby?`)) {
      return
    }
    setError(null)
    setBusy(true)
    try {
      const next = await withAuthRetry((token) =>
        removeLobbyPlayer({ token, gameId: view.game_id, playerId }),
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

  async function onUseGpsCenter() {
    setError(null)
    if (!navigator.geolocation) {
      setError('Geolocation is not available in this browser.')
      return
    }
    setBusy(true)
    try {
      const position = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 0,
        })
      })
      const center = {
        lat: position.coords.latitude,
        lon: position.coords.longitude,
      }
      const next = await withAuthRetry((token) =>
        setLobbyCircle({ token, gameId: view.game_id, radiusM: radiusDraft, center }),
      )
      onView(next)
      setNote('Play circle center moved to your GPS.')
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
        {rulesSummaryLine(view.timers) ? (
          <p className="hint rules-summary">{rulesSummaryLine(view.timers)}</p>
        ) : null}
      </header>

      <section className="join-qr">
        <h2>Join QR</h2>
        {joinQr ? (
          <img src={joinQr} alt={`Join QR for ${view.join_code}`} width={220} height={220} />
        ) : (
          <p className="hint">Drawing join code…</p>
        )}
        <p className="hint join-link">{joinLink}</p>
        <p className="hint">Friends can Scan on the home screen instead of typing the code.</p>
      </section>

      <section>
        <h2>Players</h2>
        <ul>
          {view.players.map((player) => (
            <li key={player.player_id}>
              <div>
                <span>{displayNameFor(player.player_id, player.display_name)}</span>
                <span className="meta">
                  {player.role}
                  {player.is_host ? ' · host' : ''}
                </span>
              </div>
              <div className="player-actions">
                {isHost ? (
                  <div className="chip-row">
                    <button
                      type="button"
                      className={`chip${player.role === 'seeker' ? ' chip--active' : ''}`}
                      disabled={busy}
                      onClick={() => void onToggleRole(player.player_id, 'seeker')}
                    >
                      Seeker
                    </button>
                    <button
                      type="button"
                      className={`chip${player.role === 'hider' ? ' chip--active' : ''}`}
                      disabled={busy}
                      onClick={() => void onToggleRole(player.player_id, 'hider')}
                    >
                      Hider
                    </button>
                  </div>
                ) : null}
                {isHost && player.player_id !== view.you.player_id && !player.is_host ? (
                  <button
                    type="button"
                    className="chip chip--danger"
                    disabled={busy}
                    onClick={() => void onRemovePlayer(player.player_id, player.display_name)}
                  >
                    Remove
                  </button>
                ) : null}
                {player.player_id !== view.you.player_id ? (
                  <div className="chip-row safety-row">
                    <button
                      type="button"
                      className="chip"
                      onClick={() =>
                        setPendingBlock({
                          id: player.player_id,
                          name: player.display_name,
                        })
                      }
                    >
                      Block
                    </button>
                    <a
                      className="chip"
                      href={reportMailto({
                        gameId: view.game_id,
                        playerId: player.player_id,
                        displayName: player.display_name,
                        supportEmail: SUPPORT_EMAIL,
                      })}
                    >
                      Report
                    </a>
                  </div>
                ) : null}
              </div>
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
              min={MIN_ARENA_RADIUS_M}
              max={MAX_ARENA_RADIUS_M}
              step={50}
              value={radiusDraft}
              onChange={(e) => setRadiusDraft(Number(e.target.value))}
              aria-invalid={radiusDraftError !== null}
            />
          </label>
          {radiusDraftError ? (
            <p className="error" role="alert">
              {radiusDraftError}
            </p>
          ) : null}
          <button
            type="button"
            className="secondary"
            disabled={busy || radiusDraft === radiusNow || radiusDraftError !== null}
            onClick={() => void onApplyRadius()}
          >
            Apply radius
          </button>
          <button
            type="button"
            className="secondary"
            disabled={busy || radiusDraftError !== null}
            onClick={() => void onUseGpsCenter()}
          >
            Use my GPS as center
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

      <button type="button" className="linkish" onClick={() => setPendingLeave(true)}>
        Leave
      </button>
      {pendingLeave ? (
        <ConfirmDialog
          title="Leave this hunt?"
          confirmLabel="Leave"
          onConfirm={() => {
            setPendingLeave(false)
            onLeave()
          }}
          onCancel={() => setPendingLeave(false)}
        />
      ) : null}
      {pendingBlock ? (
        <ConfirmDialog
          title="Block this player?"
          message="Their name is masked on this device. You can unblock them in Account."
          confirmLabel="Block"
          onConfirm={() => {
            blockPlayer(pendingBlock.id, pendingBlock.name)
            setPendingBlock(null)
            setNote('Player blocked on this device.')
          }}
          onCancel={() => setPendingBlock(null)}
        />
      ) : null}
    </main>
  )
}
