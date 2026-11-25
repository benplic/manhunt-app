import { describe, expect, it } from 'vitest'
import {
  ALERT_EXPIRY_MS,
  ALERT_QUEUE_CAP,
  ALERT_SHOW_MS,
  AlertQueue,
  type LiveAlert,
} from './alertQueue'

function alert(key: string, priority: LiveAlert['priority'], text = key): LiveAlert {
  return { key, text, priority, tone: 'info' }
}

/** Drain the queue the way the UI does: wait for each alert's 4 s, then advance. */
function drain(queue: AlertQueue, start: number): { order: string[]; end: number } {
  const order: string[] = []
  let now = start
  while (queue.current) {
    order.push(queue.current.key)
    now += ALERT_SHOW_MS
    queue.advance(now)
  }
  return { order, end: now }
}

describe('AlertQueue', () => {
  it('shows the first alert immediately', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('a', 3), 0)
    expect(queue.current?.key).toBe('a')
    expect(queue.nextWakeAt()).toBe(ALERT_SHOW_MS)
  })

  it('queues a same-priority alert and shows it after 4 s', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('a', 3), 0)
    queue.enqueue(alert('b', 3), 1000)
    expect(queue.current?.key).toBe('a')
    expect(queue.queued.map((q) => q.key)).toEqual(['b'])

    expect(queue.advance(3999)).toBe(false)
    expect(queue.current?.key).toBe('a')
    expect(queue.advance(4000)).toBe(true)
    expect(queue.current?.key).toBe('b')
    expect(queue.current?.shownAt).toBe(4000)
    expect(queue.queued).toEqual([])
  })

  it('queues, and never skips, a lower-priority alert behind a higher one', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('tag', 1), 0)
    queue.enqueue(alert('ping', 3), 500)
    queue.enqueue(alert('dark', 2), 600)

    expect(queue.current?.key).toBe('tag')
    expect(queue.queued.map((q) => q.key)).toEqual(['dark', 'ping'])

    const { order } = drain(queue, 0)
    expect(order).toEqual(['tag', 'dark', 'ping'])
  })

  it('does not drop a queued lower-priority alert while a higher one keeps arriving', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('ping', 3), 0)
    queue.enqueue(alert('tag-1', 1), 100)
    queue.enqueue(alert('tag-2', 1), 200)
    queue.enqueue(alert('tag-3', 1), 300)

    const { order } = drain(queue, 300)
    expect(order).toEqual(['tag-1', 'tag-2', 'tag-3', 'ping'])
  })

  it('lets a higher-priority alert take the slot and resumes the interrupted one', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('ping', 3), 0)
    queue.enqueue(alert('tag', 1), 1500)

    expect(queue.current?.key).toBe('tag')
    expect(queue.queued.map((q) => q.key)).toEqual(['ping'])

    queue.advance(1500 + ALERT_SHOW_MS)
    expect(queue.current?.key).toBe('ping')
    // Full 4 seconds again, not the 2.5 s that were left.
    expect(queue.current?.shownAt).toBe(1500 + ALERT_SHOW_MS)
    expect(queue.nextWakeAt()).toBe(1500 + 2 * ALERT_SHOW_MS)
  })

  it('puts the interrupted alert at the front of its own tier', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('ping-a', 3), 0)
    queue.enqueue(alert('ping-b', 3), 100)
    queue.enqueue(alert('pill', 4), 200)
    queue.enqueue(alert('tag', 1), 300)

    expect(queue.queued.map((q) => q.key)).toEqual(['ping-a', 'ping-b', 'pill'])
  })

  it('does not interrupt for an equal-priority alert', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('a', 1), 0)
    queue.enqueue(alert('b', 1), 10)
    expect(queue.current?.key).toBe('a')
  })

  it('gives a resumed alert a new showId so screen readers announce it again', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('ping', 3), 0)
    const first = queue.current?.showId
    queue.enqueue(alert('tag', 1), 100)
    queue.advance(100 + ALERT_SHOW_MS)
    expect(queue.current?.key).toBe('ping')
    expect(queue.current?.showId).not.toBe(first)
  })

  it('runs first in, first out within one priority', () => {
    const queue = new AlertQueue()
    for (const key of ['a', 'b', 'c', 'd']) {
      queue.enqueue(alert(key, 2), 0)
    }
    expect(drain(queue, 0).order).toEqual(['a', 'b', 'c', 'd'])
  })

  it('coalesces a duplicate of the visible alert without restarting its timer', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('dark:riley', 2, 'Riley went dark.'), 0)
    queue.enqueue(alert('dark:riley', 2, 'Riley went dark.'), 2000)
    expect(queue.queued).toEqual([])
    expect(queue.current?.shownAt).toBe(0)
  })

  it('coalesces duplicates inside the queue into one entry', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('first', 1), 0)
    for (let i = 0; i < 53; i += 1) {
      queue.enqueue(alert('dark:riley', 2, `Riley went dark (${i}).`), i)
    }
    expect(queue.queued.map((q) => q.key)).toEqual(['dark:riley'])
    expect(queue.queued[0].text).toBe('Riley went dark (52).')
  })

  it('caps the queue at 8 and drops the oldest lowest-priority entry', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('showing', 1), 0)
    queue.enqueue(alert('pill-old', 4), 1)
    queue.enqueue(alert('pill-new', 4), 2)
    for (let i = 0; i < ALERT_QUEUE_CAP - 2; i += 1) {
      queue.enqueue(alert(`ping-${i}`, 3), 3 + i)
    }
    expect(queue.queued).toHaveLength(ALERT_QUEUE_CAP)

    queue.enqueue(alert('dark', 2), 100)

    expect(queue.queued).toHaveLength(ALERT_QUEUE_CAP)
    const keys = queue.queued.map((q) => q.key)
    expect(keys).not.toContain('pill-old')
    expect(keys).toContain('pill-new')
    expect(keys[0]).toBe('dark')
  })

  it('drops an alert that waited more than 30 s without being shown', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('long', 1), 0)
    queue.enqueue(alert('stale', 3), 1000)
    queue.enqueue(alert('fresh', 3), 25_000)

    queue.advance(ALERT_EXPIRY_MS + 1001)
    expect(queue.current?.key).toBe('fresh')
  })

  it('keeps an alert that has waited exactly 30 s', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('long', 1), 0)
    queue.enqueue(alert('edge', 3), 0)
    queue.advance(ALERT_EXPIRY_MS)
    expect(queue.current?.key).toBe('edge')
  })

  it('counts an interrupted alert as waiting from the moment it was interrupted', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('ping', 3), 0)
    queue.enqueue(alert('tag', 1), 3000)
    queue.advance(3000 + ALERT_SHOW_MS)
    expect(queue.current?.key).toBe('ping')
  })

  it('after the app returns from the background keeps only the 3 highest-priority', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('now', 1), 0)
    queue.enqueue(alert('pill', 4), 1)
    queue.enqueue(alert('ping', 3), 2)
    queue.enqueue(alert('dark', 2), 3)
    queue.enqueue(alert('oob', 1), 4)
    queue.enqueue(alert('ping-2', 3), 5)

    queue.resumeFromBackground(10_000)

    expect(queue.current?.key).toBe('oob')
    expect(queue.queued.map((q) => q.key)).toEqual(['dark', 'ping'])
    expect(drain(queue, 10_000).order).toEqual(['oob', 'dark', 'ping'])
  })

  it('ten events in one second are all shown, one at a time, in priority order', () => {
    const queue = new AlertQueue()
    const events: LiveAlert[] = [
      alert('pill', 4),
      alert('ping', 3),
      alert('dark:riley', 2),
      alert('dark:riley', 2),
      alert('tag:morgan', 1),
      alert('ping', 3),
      alert('dark:casey', 2),
      alert('oob:jordan', 1),
      alert('dark:riley', 2),
      alert('pill', 4),
    ]
    events.forEach((event, index) => queue.enqueue(event, index * 100))

    const seen: string[] = []
    let now = 900
    while (queue.current) {
      seen.push(queue.current.key)
      expect(queue.current.shownAt).toBeLessThanOrEqual(now)
      now += ALERT_SHOW_MS
      queue.advance(now)
    }

    // pill, ping and dark:riley each took the slot briefly and were interrupted, then
    // resumed. Duplicates collapsed. Nothing was lost, and the order is by priority.
    expect(seen).toEqual([
      'tag:morgan',
      'oob:jordan',
      'dark:riley',
      'dark:casey',
      'ping',
      'pill',
    ])
    expect(queue.current).toBeNull()
    expect(queue.queued).toEqual([])
    expect(queue.nextWakeAt()).toBeNull()
  })

  it('never shows two alerts at once and ends cleanly when empty', () => {
    const queue = new AlertQueue()
    expect(queue.current).toBeNull()
    expect(queue.advance(1_000_000)).toBe(false)
    queue.enqueue(alert('a', 2), 0)
    queue.advance(ALERT_SHOW_MS)
    expect(queue.current).toBeNull()
    expect(queue.nextWakeAt()).toBeNull()
  })

  it('stops the clock while the surface is hidden, so nothing is consumed unseen', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('tag', 1), 0)
    queue.enqueue(alert('ping', 3), 100)

    queue.hold(1000)
    expect(queue.nextWakeAt()).toBeNull()
    expect(queue.advance(60_000)).toBe(false)
    expect(queue.current?.key).toBe('tag')

    queue.release(60_000)
    const showId = queue.current?.showId
    // The tag alert gets its full 4 s again, with a fresh showId to announce.
    expect(queue.current?.shownAt).toBe(60_000)
    expect(queue.nextWakeAt()).toBe(60_000 + ALERT_SHOW_MS)
    expect(showId).toBeGreaterThan(1)

    queue.advance(60_000 + ALERT_SHOW_MS)
    // The ping waited about 1 s of visible time, not 60 s, so it has not expired.
    expect(queue.current?.key).toBe('ping')
  })

  it('shows an alert that arrives during a hold and starts its time on release', () => {
    const queue = new AlertQueue()
    queue.hold(0)
    queue.enqueue(alert('oob', 1), 5000)
    expect(queue.current?.key).toBe('oob')
    expect(queue.nextWakeAt()).toBeNull()

    queue.release(9000)
    expect(queue.current?.shownAt).toBe(9000)
    expect(queue.nextWakeAt()).toBe(9000 + ALERT_SHOW_MS)
  })

  it('shows an alert that arrives while the slot is idle after a gap', () => {
    const queue = new AlertQueue()
    queue.enqueue(alert('a', 2), 0)
    queue.advance(ALERT_SHOW_MS)
    queue.enqueue(alert('b', 4), 9_000)
    expect(queue.current?.key).toBe('b')
    expect(queue.current?.shownAt).toBe(9_000)
  })
})
