import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { GameSocket, type WsEvent, wsUrlForGame } from './ws'

class FakeWebSocket {
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
      data: { token: 'tok', last_seq: 3 },
    })
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
      data: { token: 'tok', last_seq: 12 },
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
})
