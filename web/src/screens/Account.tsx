import { useState } from 'react'
import { PRIVACY_URL, SUPPORT_EMAIL } from '../api/legal'
import {
  anonymizedName,
  listBlockedPlayers,
  unblockPlayer,
  type BlockedPlayerEntry,
} from '../social/blockList'
import './Account.css'

type Props = {
  onClose: () => void
}

export function Account({ onClose }: Props) {
  const [blocked, setBlocked] = useState<BlockedPlayerEntry[]>(() => listBlockedPlayers())

  function onUnblock(playerId: string) {
    unblockPlayer(playerId)
    setBlocked(listBlockedPlayers())
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
    </main>
  )
}
