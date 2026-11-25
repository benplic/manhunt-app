import { useEffect, useState } from 'react'
import type { ViewTimers } from '../api/types'
import {
  RULE_LIMITS,
  draftFromTimers,
  overridesFromDraft,
  ruleErrors,
  type RuleOverrides,
} from '../game/lobbyRules'

type Props = {
  timers: ViewTimers | undefined
  busy: boolean
  onApply: (overrides: RuleOverrides) => void | Promise<void>
}

/** Host-only timer inputs for the lobby. Everyone else sees the live summary line instead. */
export function LobbyRules({ timers, busy, onApply }: Props) {
  const current = draftFromTimers(timers)
  const [draft, setDraft] = useState(current)
  const { headStartS, timeLimitMin, revealIntervalS } = current

  // Another edit (or a rejoin) changes the server values; follow them rather than keep stale inputs.
  useEffect(() => {
    setDraft({ headStartS, timeLimitMin, revealIntervalS })
  }, [headStartS, timeLimitMin, revealIntervalS])

  const errors = ruleErrors(draft, current)
  const overrides = overridesFromDraft(draft, current)

  return (
    <section aria-label="Rules">
      <h2>Rules</h2>
      <label>
        Head start (seconds)
        <input
          type="number"
          min={RULE_LIMITS.headStartS.min}
          max={RULE_LIMITS.headStartS.max}
          value={draft.headStartS}
          onChange={(e) => setDraft({ ...draft, headStartS: Number(e.target.value) })}
        />
      </label>
      <label>
        Time limit (minutes)
        <input
          type="number"
          min={RULE_LIMITS.timeLimitMin.min}
          max={RULE_LIMITS.timeLimitMin.max}
          value={draft.timeLimitMin}
          onChange={(e) => setDraft({ ...draft, timeLimitMin: Number(e.target.value) })}
        />
      </label>
      {draft.revealIntervalS !== null ? (
        <label>
          Hider reveal every (seconds)
          <input
            type="number"
            min={RULE_LIMITS.revealIntervalS.min}
            max={RULE_LIMITS.revealIntervalS.max}
            value={draft.revealIntervalS}
            onChange={(e) => setDraft({ ...draft, revealIntervalS: Number(e.target.value) })}
          />
        </label>
      ) : null}
      {errors.map((message) => (
        <p key={message} className="error" role="alert">
          {message}
        </p>
      ))}
      <button
        type="button"
        className="secondary"
        disabled={busy || errors.length > 0 || overrides === null}
        onClick={() => {
          if (overrides) {
            void onApply(overrides)
          }
        }}
      >
        Apply rules
      </button>
    </section>
  )
}
