import type { WsEvent } from '../api/ws'

export type TagAnnouncement = {
  seq: number
  text: string
}

export type TagAnnouncementQueue = {
  gameId: string | null
  items: TagAnnouncement[]
  seenSeqs: ReadonlySet<number>
}

type QueueAction =
  | { type: 'switchGame'; gameId: string }
  | { type: 'event'; gameId: string; event: WsEvent }
  | { type: 'expire'; seq: number }
  | { type: 'clear' }

export const initialTagAnnouncementQueue: TagAnnouncementQueue = {
  gameId: null,
  items: [],
  seenSeqs: new Set(),
}

export function tagAnnouncementFromEvent(event: WsEvent): TagAnnouncement | null {
  if (!event.subject_name) {
    return null
  }
  if (event.announcement === 'player_tagged') {
    return { seq: event.seq, text: `${event.subject_name} was tagged!` }
  }
  if (event.announcement === 'player_tagged_out_of_bounds') {
    return {
      seq: event.seq,
      text: `${event.subject_name} was tagged out of bounds!`,
    }
  }
  return null
}

export function tagAnnouncementQueueReducer(
  state: TagAnnouncementQueue,
  action: QueueAction,
): TagAnnouncementQueue {
  switch (action.type) {
    case 'switchGame':
      return state.gameId === action.gameId
        ? state
        : { gameId: action.gameId, items: [], seenSeqs: new Set() }
    case 'event': {
      const base =
        state.gameId === action.gameId
          ? state
          : { gameId: action.gameId, items: [], seenSeqs: new Set<number>() }
      if (base.seenSeqs.has(action.event.seq)) {
        return base
      }
      const announcement = tagAnnouncementFromEvent(action.event)
      if (!announcement) {
        return base
      }
      const seenSeqs = new Set(base.seenSeqs)
      seenSeqs.add(action.event.seq)
      return { ...base, items: [...base.items, announcement], seenSeqs }
    }
    case 'expire':
      return state.items[0]?.seq === action.seq
        ? { ...state, items: state.items.slice(1) }
        : state
    case 'clear':
      return initialTagAnnouncementQueue
  }
}
