/**
 * One-at-a-time alert presenter with a priority queue.
 *
 * Rules (see docs/superpowers/plans/2026-11-24-alert-noise.md):
 * - One alert is visible at a time, for ALERT_SHOW_MS.
 * - A lower- or equal-priority alert that arrives while another is showing WAITS in the
 *   queue. It is never skipped or overwritten.
 * - A higher-priority alert takes the slot at once. An interrupted safety or tag alert goes
 *   back to the front of its own tier and later shows again for its full time. An interrupted
 *   ping or live-update pill was already seen, so it is not replayed.
 * - A higher-priority alert also jumps ahead of every lower-priority alert in the queue.
 * - Within one priority the order is first in, first out.
 * - An alert the player has not seen is NEVER dropped (decided by the user, 2026-11-25).
 *   There is no cap, no expiry, and no trim after the page was hidden. The only merge is
 *   de-duplication by `key`: the same subject and type is one entry, with its latest words.
 *
 * Pure and clock-free: every method takes `now` in milliseconds, so tests never sleep.
 * The caller owns the timer and calls `advance` at `nextWakeAt()`.
 */

/** 1 = tag and out-of-bounds, 2 = safety "went dark", 3 = ping flash, 4 = live-update pill. */
export type AlertPriority = 1 | 2 | 3 | 4

export type AlertTone = 'info' | 'warn' | 'danger' | 'safety'

export type LiveAlert = {
  /** Subject + type, e.g. `dark:<player_id>`. The same key coalesces into one entry. */
  key: string
  text: string
  tone: AlertTone
  priority: AlertPriority
}

export type ShownAlert = LiveAlert & {
  shownAt: number
  /** New for every showing, including a resumed one, so a screen reader announces it again. */
  showId: number
}

export const ALERT_SHOW_MS = 4000

export class AlertQueue {
  current: ShownAlert | null = null
  private waiting: LiveAlert[] = []
  private showSeq = 0
  /**
   * Set while nobody can see the alert surface (a panel is open, the tab is hidden).
   * Alerts keep queueing, but the clock stops, so nothing is used up unseen.
   */
  private heldAt: number | null = null

  /** Alerts waiting for the slot, in the order they will be shown. */
  get queued(): readonly LiveAlert[] {
    return this.waiting
  }

  enqueue(alert: LiveAlert, now: number): void {
    const current = this.current
    if (current && current.key === alert.key) {
      // Same alert already on screen: refresh its text, keep its timer.
      this.current = { ...current, text: alert.text, tone: alert.tone }
      return
    }

    const existing = this.waiting.findIndex((entry) => entry.key === alert.key)
    if (existing >= 0) {
      const entry = this.waiting[existing]
      if (entry.priority === alert.priority) {
        this.waiting[existing] = { ...entry, text: alert.text, tone: alert.tone }
        return
      }
      this.waiting.splice(existing, 1)
    }

    if (!current) {
      this.show(alert, now)
      return
    }

    if (alert.priority < current.priority) {
      // A pill or ping already on screen is seen. Replaying it after a ping or tag repeated
      // the same news, so only safety and tag alerts come back after an interruption.
      if (current.priority < 3) {
        this.requeueFront(current)
      }
      this.show(alert, now)
      return
    }

    this.insertBack(alert)
  }

  /**
   * Call when the timer fires (or whenever the app wakes). Returns true if what is on
   * screen changed.
   */
  advance(now: number): boolean {
    if (this.heldAt !== null) {
      return false
    }
    if (this.current && now - this.current.shownAt < ALERT_SHOW_MS) {
      return false
    }
    const hadCurrent = this.current !== null
    this.current = null
    const next = this.waiting.shift()
    if (next) {
      this.show(next, now)
      return true
    }
    return hadCurrent
  }

  /** Millisecond timestamp for the next `advance`, or null when nothing is showing. */
  nextWakeAt(): number | null {
    if (this.heldAt !== null) {
      return null
    }
    return this.current ? this.current.shownAt + ALERT_SHOW_MS : null
  }

  /** The alert surface is not visible. Alerts keep queueing, but the clock stops. */
  hold(now: number): void {
    if (this.heldAt === null) {
      this.heldAt = now
    }
  }

  /**
   * The surface is visible again. The showing alert starts its 4 s over (with a new
   * showId so a screen reader announces it), because nobody saw it while it was held.
   */
  release(now: number): void {
    if (this.heldAt === null) {
      return
    }
    this.heldAt = null
    if (this.current) {
      this.showSeq += 1
      this.current = { ...this.current, shownAt: now, showId: this.showSeq }
    }
  }

  get isHeld(): boolean {
    return this.heldAt !== null
  }

  private show(alert: LiveAlert, now: number): void {
    this.showSeq += 1
    this.current = {
      key: alert.key,
      text: alert.text,
      tone: alert.tone,
      priority: alert.priority,
      shownAt: now,
      showId: this.showSeq,
    }
  }

  /** Back to the front of its own tier, so it shows again before later arrivals. */
  private requeueFront(alert: LiveAlert): void {
    const entry: LiveAlert = {
      key: alert.key,
      text: alert.text,
      tone: alert.tone,
      priority: alert.priority,
    }
    const at = this.waiting.findIndex((other) => other.priority >= entry.priority)
    this.waiting.splice(at === -1 ? this.waiting.length : at, 0, entry)
  }

  /** Behind everything of the same or higher priority, ahead of anything lower. */
  private insertBack(entry: LiveAlert): void {
    let at = this.waiting.length
    while (at > 0 && this.waiting[at - 1].priority > entry.priority) {
      at -= 1
    }
    this.waiting.splice(at, 0, entry)
  }
}
