import type { FixReading } from '../game/fixFreshness'
import './Roster.css'

const BAR_COUNT = 4

/**
 * Four bars for how recently a player's location was heard. This is freshness of the last
 * fix, never radio signal strength. Filled bars are solid and empty ones are outlines, so
 * the meaning never depends on color alone.
 */
export function FixBars({ reading }: { reading: FixReading }) {
  return (
    <span
      role="img"
      className={`fix-bars fix-bars--${reading.bars}`}
      aria-label={reading.label}
      title={reading.label}
    >
      {Array.from({ length: BAR_COUNT }, (_, index) => (
        <span
          key={index}
          aria-hidden="true"
          className={`fix-bars__bar${index < reading.bars ? ' fix-bars__bar--on' : ''}`}
          style={{ height: `${5 + index * 3}px` }}
        />
      ))}
    </span>
  )
}
