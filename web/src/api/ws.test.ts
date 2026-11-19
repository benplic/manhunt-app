import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { GameSocket, wsUrlForGame } from './ws'

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

  close() {
    this.readyState = FakeWebSocket.CLOSED
    this.onclose?.(new CloseEvent('close'))
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

  async function openSocket(socket: GameSocket, opts: { url?: string; token?: string; lastSeq?: number } = {}) {
    socket.connect({
      url: opts.url ?? 'wss://example.test/ws',
      token: opts.token ?? 'tok',
      lastSeq: opts.lastSeq,
    })
    // FakeWebSocket opens on a microtask; do not runAllTimers (ping interval).
    await Promise.resolve()
    await Promise.resolve()
    return FakeWebSocket.instances[0]
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

  it('throttles location to at most once per second', async () => {
    const socket = new GameSocket()
    const ws = await openSocket(socket)
    ws.sent = []

    socket.sendLocation({ lat: 1, lon: 2, accuracyM: 5 })
    socket.sendLocation({ lat: 1.1, lon: 2.1, accuracyM: 5 })
    expect(ws.sent).toHaveLength(1)

    await vi.advanceTimersByTimeAsync(1000)
    socket.sendLocation({ lat: 1.2, lon: 2.2, accuracyM: 5 })
    expect(ws.sent).toHaveLength(2)
    expect(JSON.parse(ws.sent[0]).type).toBe('location')
    expect(JSON.parse(ws.sent[0]).data).toEqual({
      lat: 1,
      lon: 2,
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
})
