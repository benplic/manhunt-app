import { beforeEach, describe, expect, it } from 'vitest'
import type { WsEvent } from '../api/ws'
import { blockPlayer } from '../social/blockList'
import {
  initialTagAnnouncementQueue,
  tagAnnouncementFromEvent,
  tagAnnouncementQueueReducer,
} from './tagAnnouncements'

function event(overrides: Partial<WsEvent> = {}): WsEvent {
  return {
    seq: 1,
    type: 'tag',
    text: 'prose is not the announcement contract',
    tone: 'danger',
    player_id: 'hider-1',
    announcement: 'player_tagged',
    subject_name: 'Riley',
    ...overrides,
  }
}

describe('tag announcements', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('builds exact normal and out-of-bounds copy from structured fields', () => {
    expect(tagAnnouncementFromEvent(event())?.text).toBe('Riley was tagged!')
    expect(
      tagAnnouncementFromEvent(
        event({
          seq: 2,
          announcement: 'player_tagged_out_of_bounds',
          subject_name: 'Morgan',
        }),
      )?.text,
    ).toBe('Morgan was tagged out of bounds!')
  })

  it('does not parse prose or infer announcements from unrelated events', () => {
    expect(
      tagAnnouncementFromEvent(
        event({
          type: 'tag',
          text: 'Riley was tagged!',
          announcement: null,
          subject_name: null,
        }),
      ),
    ).toBeNull()
    expect(
      tagAnnouncementFromEvent(
        event({
          type: 'player_status',
          text: 'Riley is eliminated',
          announcement: 'other_event',
        }),
      ),
    ).toBeNull()
  })

  it('masks a blocked subject using the structured player id', () => {
    blockPlayer('hider-1', 'Riley')

    expect(tagAnnouncementFromEvent(event())?.text).toBe('Blocked Player #1 was tagged!')
  })

  it('queues back-to-back events FIFO and expires only the current item', () => {
    let state = tagAnnouncementQueueReducer(initialTagAnnouncementQueue, {
      type: 'event',
      gameId: 'game-1',
      event: event({ seq: 1, subject_name: 'Riley' }),
    })
    state = tagAnnouncementQueueReducer(state, {
      type: 'event',
      gameId: 'game-1',
      event: event({ seq: 2, subject_name: 'Morgan' }),
    })

    expect(state.items.map((item) => item.text)).toEqual([
      'Riley was tagged!',
      'Morgan was tagged!',
    ])

    state = tagAnnouncementQueueReducer(state, { type: 'expire', seq: 1 })
    expect(state.items.map((item) => item.text)).toEqual(['Morgan was tagged!'])
  })

  it('deduplicates by sequence during one game and resets for a new game', () => {
    let state = tagAnnouncementQueueReducer(initialTagAnnouncementQueue, {
      type: 'event',
      gameId: 'game-1',
      event: event({ seq: 8 }),
    })
    state = tagAnnouncementQueueReducer(state, {
      type: 'event',
      gameId: 'game-1',
      event: event({ seq: 8 }),
    })
    expect(state.items).toHaveLength(1)

    state = tagAnnouncementQueueReducer(state, {
      type: 'event',
      gameId: 'game-2',
      event: event({ seq: 8, subject_name: 'Morgan' }),
    })
    expect(state.items.map((item) => item.text)).toEqual(['Morgan was tagged!'])
  })

  it('clears queued announcements', () => {
    const queued = tagAnnouncementQueueReducer(initialTagAnnouncementQueue, {
      type: 'event',
      gameId: 'game-1',
      event: event(),
    })
    expect(tagAnnouncementQueueReducer(queued, { type: 'clear' })).toEqual(
      initialTagAnnouncementQueue,
    )
  })
})
