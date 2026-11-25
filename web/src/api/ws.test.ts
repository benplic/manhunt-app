import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  GameSocket,
  RECONNECT_DEBOUNCE_MS,
  RESEND_FIX_MAX_AGE_MS,
  STABLE_CONNECTION_MS,
  type ClientInfo,
  type WsEvent,
  wsUrlForGame,
} from './ws'

class FakeWebSocket {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSED = 3
  readyState = FakeWebSocket.OPEN
  sent: string[] = []
  onopen: ((ev: Event) => void) | null = null
  onmessage: ((ev: MessageEvent) => void) | null = null
  onclose: ((ev: CloseEvent) => void) | null = null
  onerror: ((ev: Event) => void) | null = null
  url: string

  constructor(url: string) {
    this.url = url
    FakeWebSocket.instances.push(this)
    queueMicrotask(() => this.onopen?.(new Event('open')))
  }

  static instances: FakeWebSocket[] = []

  send(data: string) {
    this.sent.push(data)
  }

  close(code = 1000) {
    this.readyState = FakeWebSocket.CLOSED
    this.onclose?.(new CloseEvent('close', { code }))
  }

  emit(payload: unknown) {
    this.onmessage?.(new MessageEvent('message', { data: JSON.stringify(payload) }))
  }
}

describe('wsUrlForGame', () => {
  it('maps https API origin to wss game path', () => {
    expect(wsUrlForGame('https://manhunt.pivotlattice.app', 'game-1')).toBe(
      'wss://manhunt.pivotlattice.app/v1/games/game-1/ws',
    )
  })
})

const CLIENT: ClientInfo = { platform: 'web', app_version: 'test', os_version: 'TestOS 1.0' }

describe('GameSocket', () => {
  beforeEach(() => {
    FakeWebSocket.instances = []
    vi.stubGlobal('WebSocket', FakeWebSocket as unknown as typeof WebSocket)
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  async function openSocket(
    socket: GameSocket,
    opts: { url?: string; token?: string; lastSeq?: number; getToken?: () => string } = {},
  ) {
    socket.connect({
      url: opts.url ?? 'wss://example.test/ws',
      token: opts.token ?? 'tok',
      getToken: opts.getToken,
      lastSeq: opts.lastSeq,
      client: CLIENT,
    })
    await Promise.resolve()
    await Promise.resolve()
    return FakeWebSocket.instances[FakeWebSocket.instances.length - 1]
  }

  it('sends hello with token on open', async () => {
    const socket = new GameSocket()
    const ws = await openSocket(socket, {
      url: 'wss://example.test/v1/games/g/ws',
      token: 'tok',
      lastSeq: 3,
    })
    expect(JSON.parse(ws.sent[0])).toEqual({
      type: 'hello',
      data: { token: 'tok', last_seq: 3, client: CLIENT },
    })
    socket.disconnect()
  })

  it('identifies the platform as web by default', async () => {
    const socket = new GameSocket()
    socket.connect({ url: 'wss://example.test/ws', token: 'tok' })
    await Promise.resolve()
    await Promise.resolve()
    const ws = FakeWebSocket.instances[FakeWebSocket.instances.length - 1]
    const hello = JSON.parse(ws.sent[0])
    expect(hello.data.client.platform).toBe('web')
    expect(typeof hello.data.client.app_version).toBe('string')
    expect(typeof hello.data.client.os_version).toBe('string')
    socket.disconnect()
  })

  it('applies view, qr_token, and error handlers', async () => {
    const socket = new GameSocket()
    const onView = vi.fn()
    const onQr = vi.fn()
    const onError = vi.fn()
    socket.onView = onView
    socket.onQr = onQr
    socket.onError = onError
    const ws = await openSocket(socket)

    ws.emit({
      type: 'view',
      data: {
        game_id: 'g',
        join_code: 'ABCDEF',
        phase: 'active',
        you: { player_id: 'u1', role: 'hider', status: 'active', is_host: true },
        players: [],
      },
    })
    ws.emit({ type: 'qr_token', data: { token: 'qr-1', expires_at: '2099-01-01T00:00:00Z' } })
    ws.emit({ type: 'error', data: { code: 'VALIDATION_FAILED', message: 'too fast' } })

    expect(onView).toHaveBeenCalledWith(expect.objectContaining({ phase: 'active' }))
    expect(onQr).toHaveBeenCalledWith('qr-1')
    expect(onError).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'VALIDATION_FAILED', message: 'too fast' }),
    )
    socket.disconnect()
  })

  it('delivers every structured event field without parsing its prose', async () => {
    const socket = new GameSocket()
    const received: WsEvent[] = []
    socket.onEvent = (event) => received.push(event)
    const ws = await openSocket(socket)

    ws.emit({
      type: 'event',
      data: {
        seq: 14,
        type: 'out_of_bounds',
        text: 'timeline prose that clients must ignore',
        tone: 'danger',
        player_id: 'hider-1',
        announcement: 'player_tagged_out_of_bounds',
        subject_name: 'Riley',
      },
    })

    expect(received).toEqual([
      {
        seq: 14,
        type: 'out_of_bounds',
        text: 'timeline prose that clients must ignore',
        tone: 'danger',
        player_id: 'hider-1',
        announcement: 'player_tagged_out_of_bounds',
        subject_name: 'Riley',
      },
    ])
    socket.disconnect()
  })

  it('delivers a sequence only once while keeping it for reconnect', async () => {
    const socket = new GameSocket()
    const onEvent = vi.fn()
    socket.onEvent = onEvent
    const ws = await openSocket(socket)
    const payload = {
      type: 'event',
      data: {
        seq: 12,
        type: 'tag',
        text: 'tagged',
        tone: 'danger',
        player_id: 'hider-1',
        announcement: 'player_tagged',
        subject_name: 'Riley',
      },
    }

    ws.emit(payload)
    ws.emit(payload)

    expect(onEvent).toHaveBeenCalledTimes(1)
    expect(socket.lastSeq).toBe(12)
    socket.disconnect()
  })

  it('coalesces location bursts to the latest fix within one second', async () => {
    const socket = new GameSocket()
    const ws = await openSocket(socket)
    ws.sent = []

    socket.sendLocation({ lat: 1, lon: 2, accuracyM: 5 })
    socket.sendLocation({ lat: 1.1, lon: 2.1, accuracyM: 5 })
    expect(ws.sent).toHaveLength(1)

    await vi.advanceTimersByTimeAsync(1000)
    expect(ws.sent).toHaveLength(2)
    expect(JSON.parse(ws.sent[1]).data).toEqual({
      lat: 1.1,
      lon: 2.1,
      accuracy_m: 5,
      flag: 'normal',
    })
    socket.disconnect()
  })

  it('sends ping every 15 seconds', async () => {
    const socket = new GameSocket()
    const ws = await openSocket(socket)
    ws.sent = []

    await vi.advanceTimersByTimeAsync(15000)
    expect(JSON.parse(ws.sent[0])).toEqual({ type: 'ping', data: {} })
    socket.disconnect()
  })

  it('reconnects after an unexpected close and keeps lastSeq', async () => {
    const socket = new GameSocket()
    const ws = await openSocket(socket, { lastSeq: 9 })
    ws.emit({ type: 'event', data: { seq: 12, type: 'tag', text: 'tagged' } })
    expect(socket.lastSeq).toBe(12)

    ws.close(1006)
    await vi.advanceTimersByTimeAsync(1500)
    await Promise.resolve()
    await Promise.resolve()

    expect(FakeWebSocket.instances.length).toBeGreaterThan(1)
    const reopened = FakeWebSocket.instances[FakeWebSocket.instances.length - 1]
    expect(JSON.parse(reopened.sent[0])).toEqual({
      type: 'hello',
      data: { token: 'tok', last_seq: 12, client: CLIENT },
    })
    socket.disconnect()
  })

  it('does not reconnect after a 4403 membership close', async () => {
    const socket = new GameSocket()
    const onRemoved = vi.fn()
    socket.onRemoved = onRemoved
    const ws = await openSocket(socket)
    const before = FakeWebSocket.instances.length
    ws.close(4403)
    await vi.advanceTimersByTimeAsync(20000)
    expect(onRemoved).toHaveBeenCalled()
    expect(FakeWebSocket.instances.length).toBe(before)
    socket.disconnect()
  })

  describe('connection health', () => {
    const settle = async () => {
      await Promise.resolve()
      await Promise.resolve()
    }

    async function connected(socket: GameSocket) {
      const ws = await openSocket(socket)
      ws.emit({ type: 'welcome', data: { player_id: 'u1' } })
      return ws
    }

    it('re-sends the latest fix right after welcome, without waiting for the throttle', async () => {
      const socket = new GameSocket()
      const ws = await openSocket(socket)
      // The socket is open but welcome has not arrived: the fix is buffered, not lost.
      socket.sendLocation({ lat: 1, lon: 2, accuracyM: 5 })
      socket.sendLocation({ lat: 3, lon: 4, accuracyM: 6 })
      ws.sent = []

      ws.emit({ type: 'welcome', data: {} })

      const locations = ws.sent.map((raw) => JSON.parse(raw)).filter((m) => m.type === 'location')
      expect(locations).toHaveLength(1)
      expect(locations[0].data).toEqual({ lat: 3, lon: 4, accuracy_m: 6, flag: 'normal' })
      // The throttled pending send was superseded, so nothing else is flushed later.
      ws.sent = []
      await vi.advanceTimersByTimeAsync(1500)
      expect(ws.sent.filter((raw) => JSON.parse(raw).type === 'location')).toHaveLength(0)
      socket.disconnect()
    })

    it('does not re-send a fix older than the resend limit', async () => {
      const socket = new GameSocket()
      const ws = await openSocket(socket)
      socket.sendLocation({ lat: 1, lon: 2, accuracyM: 5 })
      await vi.advanceTimersByTimeAsync(RESEND_FIX_MAX_AGE_MS + 1000)
      ws.sent = []
      ws.emit({ type: 'welcome', data: {} })
      expect(ws.sent.filter((raw) => JSON.parse(raw).type === 'location')).toHaveLength(0)
      socket.disconnect()
    })

    it('reconnects immediately on the online event and resets the backoff', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      ws.close(1006)
      // Drive the backoff up: a second failure before the first retry fires.
      const before = FakeWebSocket.instances.length

      window.dispatchEvent(new Event('online'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before + 1)
      socket.disconnect()
    })

    it('replaces a half-open socket on online instead of waiting for it to time out', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      const before = FakeWebSocket.instances.length

      window.dispatchEvent(new Event('online'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before + 1)
      expect(ws.readyState).toBe(FakeWebSocket.CLOSED)
      socket.disconnect()
    })

    it('reconnects when the tab becomes visible and the socket is dead', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      ws.close(1006)
      const before = FakeWebSocket.instances.length

      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
      document.dispatchEvent(new Event('visibilitychange'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before + 1)
      socket.disconnect()
      vi.restoreAllMocks()
    })

    it('leaves a healthy socket alone when the tab becomes visible', async () => {
      const socket = new GameSocket()
      await connected(socket)
      const before = FakeWebSocket.instances.length

      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
      document.dispatchEvent(new Event('visibilitychange'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before)
      socket.disconnect()
      vi.restoreAllMocks()
    })

    it('ignores visibilitychange while the tab is hidden', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      ws.close(1006)
      const before = FakeWebSocket.instances.length

      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden')
      document.dispatchEvent(new Event('visibilitychange'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS)

      expect(FakeWebSocket.instances.length).toBe(before)
      socket.disconnect()
      vi.restoreAllMocks()
    })

    it('collapses a storm of triggers into one reconnect', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      ws.close(1006)
      const before = FakeWebSocket.instances.length

      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
      for (let i = 0; i < 5; i += 1) {
        window.dispatchEvent(new Event('online'))
        document.dispatchEvent(new Event('visibilitychange'))
      }
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS)
      await settle()
      // The backoff timer from the close must not open a second socket on top of it.
      await vi.advanceTimersByTimeAsync(5000)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before + 1)
      socket.disconnect()
      vi.restoreAllMocks()
    })

    it('never reconnects on a trigger after a host remove', async () => {
      const socket = new GameSocket()
      socket.onRemoved = vi.fn()
      const ws = await connected(socket)
      ws.emit({ type: 'removed', data: {} })
      const before = FakeWebSocket.instances.length

      window.dispatchEvent(new Event('online'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS * 4)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before)
    })

    it('stops listening for triggers after disconnect', async () => {
      const socket = new GameSocket()
      await connected(socket)
      socket.disconnect()
      const before = FakeWebSocket.instances.length

      window.dispatchEvent(new Event('online'))
      await vi.advanceTimersByTimeAsync(RECONNECT_DEBOUNCE_MS * 4)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before)
    })

    it('keeps backing off while connections flap, and resets after a stable one', async () => {
      const socket = new GameSocket()
      vi.spyOn(Math, 'random').mockReturnValue(0)
      const first = await connected(socket)
      // Drops 2 s after welcome: not stable, so the next delay doubles instead of resetting.
      await vi.advanceTimersByTimeAsync(2000)
      first.close(1006)
      expect(socket.health().failureStreak).toBe(1)
      await vi.advanceTimersByTimeAsync(1000)
      await settle()
      const second = FakeWebSocket.instances[FakeWebSocket.instances.length - 1]
      expect(second).not.toBe(first)
      second.emit({ type: 'welcome', data: {} })
      await vi.advanceTimersByTimeAsync(2000)
      second.close(1006)
      expect(socket.health().failureStreak).toBe(2)

      // The streak says this is the 2nd retry: it waits 2 s, not 1 s.
      const count = FakeWebSocket.instances.length
      await vi.advanceTimersByTimeAsync(1500)
      expect(FakeWebSocket.instances.length).toBe(count)
      await vi.advanceTimersByTimeAsync(600)
      await settle()
      expect(FakeWebSocket.instances.length).toBe(count + 1)

      // A connection that stays up resets both the streak and the backoff.
      const third = FakeWebSocket.instances[FakeWebSocket.instances.length - 1]
      third.emit({ type: 'welcome', data: {} })
      await vi.advanceTimersByTimeAsync(STABLE_CONNECTION_MS)
      expect(socket.health().failureStreak).toBe(0)
      third.close(1006)
      const afterThird = FakeWebSocket.instances.length
      await vi.advanceTimersByTimeAsync(1100)
      await settle()
      expect(FakeWebSocket.instances.length).toBe(afterThird + 1)
      socket.disconnect()
      vi.restoreAllMocks()
    })

    it('drops and reconnects a welcomed socket that has gone silent (half-open)', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      const before = FakeWebSocket.instances.length

      // Pings at 15 s still count as fresh; at 30 s the socket has been silent for 30 s.
      await vi.advanceTimersByTimeAsync(30_000)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before + 1)
      expect(ws.readyState).toBe(FakeWebSocket.CLOSED)
      expect(socket.health().failureStreak).toBe(1)
      socket.disconnect()
    })

    it('reconnects a socket that opened but never received welcome', async () => {
      const socket = new GameSocket()
      const ws = await openSocket(socket)
      const before = FakeWebSocket.instances.length

      await vi.advanceTimersByTimeAsync(30_000)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before + 1)
      expect(ws.readyState).toBe(FakeWebSocket.CLOSED)
      socket.disconnect()
    })

    it('ignores the late close of a socket that was already replaced', async () => {
      const socket = new GameSocket()
      const old = await openSocket(socket)
      socket.disconnect()
      const fresh = await openSocket(socket)
      const before = FakeWebSocket.instances.length

      // A real browser can fire the old socket's close after the new one is up.
      old.onclose?.(new CloseEvent('close', { code: 1006 }))
      await vi.advanceTimersByTimeAsync(5000)
      await settle()

      expect(FakeWebSocket.instances.length).toBe(before)
      expect(fresh.readyState).toBe(FakeWebSocket.OPEN)
      socket.disconnect()
    })

    it('keeps a socket that keeps hearing from the server', async () => {
      const socket = new GameSocket()
      const ws = await connected(socket)
      const before = FakeWebSocket.instances.length

      for (let i = 0; i < 4; i += 1) {
        await vi.advanceTimersByTimeAsync(10_000)
        ws.emit({ type: 'view', data: {} })
      }

      expect(FakeWebSocket.instances.length).toBe(before)
      socket.disconnect()
    })

    it('reports health for the meter', async () => {
      const socket = new GameSocket()
      expect(socket.health()).toEqual({ connected: false, failureStreak: 0, lastMessageAt: null })
      const ws = await openSocket(socket)
      expect(socket.health().connected).toBe(false)
      ws.emit({ type: 'welcome', data: {} })
      const health = socket.health()
      expect(health.connected).toBe(true)
      expect(health.lastMessageAt).toBe(Date.now())
      ws.emit({ type: 'pong', data: {} })
      await vi.advanceTimersByTimeAsync(3000)
      ws.emit({ type: 'pong', data: {} })
      expect(socket.health().lastMessageAt).toBe(Date.now())
      socket.disconnect()
    })
  })
})
