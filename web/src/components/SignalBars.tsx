import { useEffect, useState } from 'react'
import type { SocketHealth } from '../api/ws'
import {
  meterAriaLabel,
  meterExplanation,
  socketMeter,
  type MeterReading,
} from '../game/socketMeter'

type Props = {
  /** Read on every refresh. Returning null hides the meter (no socket yet). */
  getHealth: () => SocketHealth | null
  /** The explanation goes through the alert queue; this component never renders it. */
  onExplain: (text: string) => void
  /** Injectable for tests. */
  now?: () => number
  /** How often the meter re-reads the socket. The 5 s window needs about 1 s resolution. */
  refreshMs?: number
}

const BAR_COUNT = 4

function readMeter(
  health: SocketHealth,
  now: number,
): { reading: MeterReading; ageMs: number | null } {
  const ageMs = health.lastMessageAt === null ? null : Math.max(0, now - health.lastMessageAt)
  const reading = socketMeter({
    connected: health.connected,
    failureStreak: health.failureStreak,
    lastMessageAgeMs: ageMs,
    offline: typeof navigator !== 'undefined' && navigator.onLine === false,
  })
  return { reading, ageMs }
}

/** Four bars beside Settings. Filled bars are solid; empty ones are outlines, so it is not color-only. */
export function SignalBars({ getHealth, onExplain, now = Date.now, refreshMs = 1000 }: Props) {
  const [, setTick] = useState(0)
  useEffect(() => {
    const id = window.setInterval(() => setTick((n) => n + 1), refreshMs)
    return () => window.clearInterval(id)
  }, [refreshMs])

  const health = getHealth()
  if (!health) {
    return null
  }
  const { reading, ageMs } = readMeter(health, now())

  return (
    <button
      type="button"
      className={`signal-bars signal-bars--${reading.label}`}
      aria-label={meterAriaLabel(reading)}
      title={meterAriaLabel(reading)}
      onClick={() => onExplain(meterExplanation(reading, ageMs))}
    >
      {Array.from({ length: BAR_COUNT }, (_, index) => (
        <span
          key={index}
          aria-hidden="true"
          className={`signal-bars__bar${index < reading.bars ? ' signal-bars__bar--on' : ''}`}
          style={{ height: `${6 + index * 4}px` }}
        />
      ))}
      {reading.bars <= 1 ? (
        <span aria-hidden="true" className="signal-bars__flag">
          !
        </span>
      ) : null}
    </button>
  )
}
