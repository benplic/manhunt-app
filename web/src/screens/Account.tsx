import { useState } from 'react'
import { ApiError } from '../api/client'
import { deleteAccount } from '../api/auth'
import { PRIVACY_URL, SUPPORT_EMAIL } from '../api/legal'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import {
  anonymizedName,
  listBlockedPlayers,
  unblockPlayer,
  type BlockedPlayerEntry,
} from '../social/blockList'
import './Account.css'

type Props = {
  onClose: () => void
  onSignedOut: () => void
}

export function Account({ onClose, onSignedOut }: Props) {
  const [blocked, setBlocked] = useState<BlockedPlayerEntry[]>(() => listBlockedPlayers())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function onUnblock(playerId: string) {
    unblockPlayer(playerId)
    setBlocked(listBlockedPlayers())
  }

  async function onDeleteAccount() {
    if (
      !window.confirm(
        'Deletes your account on this server. This cannot be undone. Continue?',
      )
    ) {
      return
    }
    setBusy(true)
    setError(null)
    try {
      await withAuthRetry((token) => deleteAccount(token))
      onSignedOut()
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
    <main className="account">
      <header>
        <h1>Account</h1>
        <button type="button" className="secondary" onClick={onClose}>
          Close
        </button>
      </header>

      <section>
        <h2>Privacy</h2>
        <p>
          <a href={PRIVACY_URL} target="_blank" rel="noreferrer">
            Privacy policy
          </a>
        </p>
        <p>
          <a href={`mailto:${SUPPORT_EMAIL}`}>Email support</a>
        </p>
      </section>

      <section>
        <h2>Blocked players</h2>
        <p className="hint">
          Blocks stay on this browser. Their pin stays on the map as “Blocked Player #…”.
        </p>
        {blocked.length === 0 ? (
          <p className="empty">No blocked players.</p>
        ) : (
          <ul>
            {blocked.map((entry) => (
              <li key={entry.playerId}>
                <div>
                  <strong>{anonymizedName(entry.playerId) ?? 'Blocked Player'}</strong>
                  <span className="was">Was: {entry.displayName}</span>
                </div>
                <button type="button" className="secondary" onClick={() => onUnblock(entry.playerId)}>
                  Unblock
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="danger-zone">
        <h2>Delete account</h2>
        <p className="hint">
          Deletes your account on this server. This cannot be undone.
        </p>
        {error ? (
          <p className="error" role="alert">
            {error}
          </p>
        ) : null}
        <button
          type="button"
          className="danger"
          disabled={busy}
          onClick={() => void onDeleteAccount()}
        >
          {busy ? 'Deleting…' : 'Delete account'}
        </button>
      </section>
    </main>
  )
}
