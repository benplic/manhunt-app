import { useEffect, useMemo, useState } from 'react'
import type { PlayerView } from '../api/types'
import { assignAvatarStyles } from '../game/avatarStyle'
import { fixFreshness, pingIntervalFromTimers, viewerExpectsFix } from '../game/fixFreshness'
import { groupRoster, statusNote } from '../game/roster'
import { displayNameFor } from '../social/blockList'
import { FixBars } from './FixBars'
import { PlayerAvatar } from './PlayerAvatar'

type Props = {
  view: PlayerView
  onBlock: (playerId: string, displayName: string) => void
  onReport: (playerId: string, displayName: string) => void
  /** Injectable for tests. */
  now?: () => number
  /** Bars age in real time, so rows re-read the clock on this cadence. */
  refreshMs?: number
}

/** Teams, rank, points, and a freshness bar per player. Seekers first, then hiders. */
export function Leaderboard({ view, onBlock, onReport, now = Date.now, refreshMs = 5000 }: Props) {
  const [, setTick] = useState(0)
  useEffect(() => {
    const id = window.setInterval(() => setTick((n) => n + 1), refreshMs)
    return () => window.clearInterval(id)
  }, [refreshMs])

  const players = useMemo(() => view.players ?? [], [view.players])
  const sections = useMemo(() => groupRoster(players), [players])
  // Not memoized: block-list masking lives in localStorage, and a masked player's initials
  // must match their color. The roster is at most a few dozen rows.
  const styles = assignAvatarStyles(
    players.map((p) => ({ id: p.player_id, name: displayNameFor(p.player_id, p.display_name) })),
  )
  const pingIntervalS = pingIntervalFromTimers(view.timers)
  const nowMs = now()

  return (
    <div className="leaderboard">
      {sections.map((section) => (
        <section key={section.id} aria-label={section.title}>
          <h2 className="roster-section-title">{section.title}</h2>
          <ul>
            {section.rows.map(({ player, rank, points, tagged }) => {
              const shownName = displayNameFor(player.player_id, player.display_name)
              const note = statusNote(player.status)
              const reading = fixFreshness({
                location: player.location,
                status: player.status,
                pingIntervalS,
                nowMs,
                expectsFix: viewerExpectsFix({
                  viewerId: view.you.player_id,
                  viewerRole: view.you.role,
                  viewerStatus: view.you.status,
                  playerId: player.player_id,
                  playerRole: player.role,
                  phase: view.phase,
                }),
              })
              return (
                <li key={player.player_id}>
                  <div className="leaderboard__who">
                    <PlayerAvatar name={shownName} style={styles.get(player.player_id)} />
                    <div className="leaderboard__text">
                      <strong>
                        <span className="leaderboard__rank">{rank}.</span> {shownName}
                        {tagged ? <span className="roster-tagged">tagged</span> : null}
                      </strong>
                      <span>
                        {player.role}
                        {note ? ` · ${note}` : ''} · {points} pts
                      </span>
                    </div>
                    {reading ? <FixBars reading={reading} /> : null}
                  </div>
                  {player.player_id !== view.you.player_id ? (
                    <div className="chip-row">
                      <button
                        type="button"
                        className="chip"
                        onClick={() => onBlock(player.player_id, player.display_name)}
                      >
                        Block
                      </button>
                      <button
                        type="button"
                        className="chip"
                        onClick={() => onReport(player.player_id, player.display_name)}
                      >
                        Report
                      </button>
                    </div>
                  ) : null}
                </li>
              )
            })}
          </ul>
        </section>
      ))}
    </div>
  )
}
