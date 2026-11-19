import type { PlayerView } from './types'

export type WsError = {
  code: string
  message: string
}

export type ConnectOptions = {
  url: string
  token: string
  lastSeq?: number
}

export function wsUrlForGame(apiBase: string, gameId: string): string {
  const url = new URL(apiBase)
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
  url.pathname = `/v1/games/${gameId}/ws`
  url.search = ''
  url.hash = ''
  return url.toString()
}

/** Browser WebSocket for `/v1/games/{id}/ws`. Hello first; ping every 15 s. */
export class GameSocket {
  onView: ((view: PlayerView) => void) | null = null
  onQr: ((token: string) => void) | null = null
  onError: ((error: WsError) => void) | null = null
  onEvent: ((event: { seq?: number; type?: string; text?: string }) => void) | null = null

  private socket: WebSocket | null = null
  private pingTimer: ReturnType<typeof setInterval> | null = null
  private lastLocationAt = 0
  private stopped = true
  lastSeq: number | undefined

  connect(options: ConnectOptions): void {
    this.disconnect()
    this.stopped = false
    this.lastSeq = options.lastSeq
    const ws = new WebSocket(options.url)
    this.socket = ws

    ws.onopen = () => {
      if (this.stopped || this.socket !== ws) {
        return
      }
      const data: { token: string; last_seq?: number } = { token: options.token }
      if (options.lastSeq !== undefined) {
        data.last_seq = options.lastSeq
      }
      ws.send(JSON.stringify({ type: 'hello', data }))
      this.startPings()
    }

    ws.onmessage = (event) => {
      this.handleMessage(String(event.data))
    }

    ws.onclose = () => {
      this.clearPings()
    }
  }

  sendLocation(input: { lat: number; lon: number; accuracyM: number; flag?: string }): void {
    const now = Date.now()
    if (now - this.lastLocationAt < 1000) {
      return
    }
    this.lastLocationAt = now
    this.send({
      type: 'location',
      data: {
        lat: input.lat,
        lon: input.lon,
        accuracy_m: input.accuracyM,
        flag: input.flag ?? 'normal',
      },
    })
  }

  disconnect(): void {
    this.stopped = true
    this.clearPings()
    if (this.socket) {
      try {
        this.socket.close()
      } catch {
        // TODO: log unexpected close failures once we have client telemetry.
      }
      this.socket = null
    }
  }

  private startPings(): void {
    this.clearPings()
    this.pingTimer = setInterval(() => {
      this.send({ type: 'ping', data: {} })
    }, 15_000)
  }

  private clearPings(): void {
    if (this.pingTimer !== null) {
      clearInterval(this.pingTimer)
      this.pingTimer = null
    }
  }

  private send(payload: unknown): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      return
    }
    this.socket.send(JSON.stringify(payload))
  }

  private handleMessage(raw: string): void {
    let message: { type?: string; data?: Record<string, unknown> }
    try {
      message = JSON.parse(raw) as { type?: string; data?: Record<string, unknown> }
    } catch {
      return
    }
    const data = message.data ?? {}
    switch (message.type) {
      case 'view':
        this.onView?.(data as unknown as PlayerView)
        break
      case 'qr_token':
        if (typeof data.token === 'string') {
          this.onQr?.(data.token)
        }
        break
      case 'error':
        this.onError?.({
          code: String(data.code ?? 'INTERNAL'),
          message: String(data.message ?? 'Socket error'),
        })
        break
      case 'event':
        if (typeof data.seq === 'number') {
          this.lastSeq = data.seq
        }
        this.onEvent?.({
          seq: typeof data.seq === 'number' ? data.seq : undefined,
          type: typeof data.type === 'string' ? data.type : undefined,
          text: typeof data.text === 'string' ? data.text : undefined,
        })
        break
      case 'welcome':
      case 'pong':
        break
      default:
        break
    }
  }
}
