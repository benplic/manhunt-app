/**
 * One-at-a-time alert presenter with a priority queue.
 *
 * Rules (see docs/superpowers/plans/2026-11-24-alert-noise.md):
 * - One alert is visible at a time, for ALERT_SHOW_MS.
 * - A lower- or equal-priority alert that arrives while another is showing WAITS in the
 *   queue. It is never skipped or overwritten.
 * - A higher-priority alert takes the slot at once. The one it interrupted goes back to
 *   the front of its own tier and later shows again for its full time.
 * - Within one priority the order is first in, first out.
 * - The queue is bounded so it cannot turn into a wall of stale news: a cap, an expiry
 *   for alerts that waited too long, and de-duplication by `key`.
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

type Waiting = LiveAlert & { queuedAt: number }

export const ALERT_SHOW_MS = 4000
export const ALERT_QUEUE_CAP = 8
// TODO: confirm the 30 s expiry with the user (open question in the plan).
export const ALERT_EXPIRY_MS = 30_000
export const ALERT_BACKGROUND_KEEP = 3

export class AlertQueue {
  current: ShownAlert | null = null
  private waiting: Waiting[] = []
  private showSeq = 0
  /** Set while the alert surface cannot be seen. Nothing times out or expires then. */
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
      this.requeueFront(current, now)
      this.enforceCap()
      this.show(alert, now)
      return
    }

    this.insertBack({ ...alert, queuedAt: now })
    this.enforceCap()
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
    this.waiting = this.waiting.filter((entry) => now - entry.queuedAt <= ALERT_EXPIRY_MS)
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

  /**
   * The alert surface is not visible (a panel is open, the map is hidden). Alerts keep
   * arriving and queueing, but the clock stops, so nobody loses one they never saw.
   */
  hold(now: number): void {
    if (this.heldAt === null) {
      this.heldAt = now
    }
  }

  /**
   * The surface is visible again. The showing alert starts its 4 s over (with a new
   * showId so a screen reader announces it) and waiting time does not count the hold.
   */
  release(now: number): void {
    if (this.heldAt === null) {
      return
    }
    const heldFor = now - this.heldAt
    this.heldAt = null
    this.waiting = this.waiting.map((entry) => ({ ...entry, queuedAt: entry.queuedAt + heldFor }))
    if (this.current) {
      this.showSeq += 1
      this.current = { ...this.current, shownAt: now, showId: this.showSeq }
    }
  }

  get isHeld(): boolean {
    return this.heldAt !== null
  }

  /**
   * After the page was hidden: forget stale news, keep the few highest-priority alerts.
   * Returns true if what is on screen changed.
   */
  resumeFromBackground(now: number): boolean {
    this.waiting = this.waiting
      .filter((entry) => now - entry.queuedAt <= ALERT_EXPIRY_MS)
      .slice(0, ALERT_BACKGROUND_KEEP)
    return this.advance(now)
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

  /** Back to the front of its own tier. It waits from now, with a fresh 4 s ahead. */
  private requeueFront(alert: LiveAlert, now: number): void {
    const entry: Waiting = {
      key: alert.key,
      text: alert.text,
      tone: alert.tone,
      priority: alert.priority,
      queuedAt: now,
    }
    const at = this.waiting.findIndex((other) => other.priority >= entry.priority)
    this.waiting.splice(at === -1 ? this.waiting.length : at, 0, entry)
  }

  private insertBack(entry: Waiting): void {
    let at = this.waiting.length
    while (at > 0 && this.waiting[at - 1].priority > entry.priority) {
      at -= 1
    }
    this.waiting.splice(at, 0, entry)
  }

  /** Full queue: drop the oldest entry of the lowest priority. */
  private enforceCap(): void {
    while (this.waiting.length > ALERT_QUEUE_CAP) {
      const lowest = Math.max(...this.waiting.map((entry) => entry.priority))
      const victim = this.waiting.findIndex((entry) => entry.priority === lowest)
      this.waiting.splice(victim, 1)
    }
  }
}
