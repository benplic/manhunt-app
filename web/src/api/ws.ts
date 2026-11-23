import type { PlayerView } from './types'

export type WsError = {
  code: string
  message: string
}

export type WsEvent = {
  seq: number
  type: string
  text: string
  tone: string | null
  player_id: string | null
  announcement: string | null
  subject_name: string | null
}

export type ConnectOptions = {
  url: string
  /** Static token; prefer getToken when the access token can rotate. */
  token?: string
  getToken?: () => string | null | undefined
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

type PendingLocation = {
  lat: number
  lon: number
  accuracyM: number
  flag: string
}

/** Browser WebSocket for `/v1/games/{id}/ws`. Hello first; ping every 15 s; backoff reconnect. */
export class GameSocket {
  onView: ((view: PlayerView) => void) | null = null
  onQr: ((token: string) => void) | null = null
  onError: ((error: WsError) => void) | null = null
  onEvent: ((event: WsEvent) => void) | null = null
  /** Host remove / membership close — do not reconnect. */
  onRemoved: (() => void) | null = null

  private socket: WebSocket | null = null
  private pingTimer: ReturnType<typeof setInterval> | null = null
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private flushTimer: ReturnType<typeof setTimeout> | null = null
  private lastLocationAt = 0
  private pendingLocation: PendingLocation | null = null
  private stopped = true
  private reconnectDelayS = 1
  private options: ConnectOptions | null = null
  lastSeq: number | undefined

  connect(options: ConnectOptions): void {
    this.disconnect()
    this.stopped = false
    this.reconnectDelayS = 1
    this.options = options
    if (options.lastSeq !== undefined) {
      this.lastSeq = options.lastSeq
    }
    this.openSocket()
  }

  sendLocation(input: { lat: number; lon: number; accuracyM: number; flag?: string }): void {
    const payload: PendingLocation = {
      lat: input.lat,
      lon: input.lon,
      accuracyM: input.accuracyM,
      flag: input.flag ?? 'normal',
    }
    const now = Date.now()
    const wait = 1000 - (now - this.lastLocationAt)
    if (wait <= 0) {
      this.flushLocation(payload)
      return
    }
    this.pendingLocation = payload
    if (this.flushTimer === null) {
      this.flushTimer = setTimeout(() => {
        this.flushTimer = null
        if (this.pendingLocation) {
          this.flushLocation(this.pendingLocation)
          this.pendingLocation = null
        }
      }, wait)
    }
  }

  disconnect(): void {
    this.stopped = true
    this.clearPings()
    this.clearReconnect()
    if (this.flushTimer !== null) {
      clearTimeout(this.flushTimer)
      this.flushTimer = null
    }
    this.pendingLocation = null
    if (this.socket) {
      try {
        this.socket.close()
      } catch {
        // TODO: log unexpected close failures once we have client telemetry.
      }
      this.socket = null
    }
  }

  private resolveToken(): string {
    const fromGetter = this.options?.getToken?.()
    if (fromGetter) {
      return fromGetter
    }
    return this.options?.token ?? ''
  }

  private openSocket(): void {
    if (this.stopped || !this.options) {
      return
    }
    const ws = new WebSocket(this.options.url)
    this.socket = ws

    ws.onopen = () => {
      if (this.stopped || this.socket !== ws) {
        return
      }
      this.reconnectDelayS = 1
      const data: { token: string; last_seq?: number } = { token: this.resolveToken() }
      if (this.lastSeq !== undefined) {
        data.last_seq = this.lastSeq
      }
      ws.send(JSON.stringify({ type: 'hello', data }))
      this.startPings()
    }

    ws.onmessage = (event) => {
      this.handleMessage(String(event.data))
    }

    ws.onclose = (event) => {
      this.clearPings()
      if (this.socket === ws) {
        this.socket = null
      }
      if (this.stopped) {
        return
      }
      if (event.code === 4403) {
        this.markRemoved()
        return
      }
      this.scheduleReconnect()
    }
  }

  private scheduleReconnect(): void {
    this.clearReconnect()
    const jitter = Math.random() * 0.4
    const delayMs = (this.reconnectDelayS + jitter) * 1000
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      this.openSocket()
    }, delayMs)
    this.reconnectDelayS = this.reconnectDelayS >= 15 ? 15 : Math.min(this.reconnectDelayS * 2, 15)
  }

  private markRemoved(): void {
    this.stopped = true
    this.clearPings()
    this.clearReconnect()
    this.onRemoved?.()
  }

  private flushLocation(payload: PendingLocation): void {
    this.lastLocationAt = Date.now()
    this.send({
      type: 'location',
      data: {
        lat: payload.lat,
        lon: payload.lon,
        accuracy_m: payload.accuracyM,
        flag: payload.flag,
      },
    })
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

  private clearReconnect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
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
        if (
          typeof data.seq !== 'number' ||
          typeof data.type !== 'string' ||
          typeof data.text !== 'string'
        ) {
          break
        }
        if (this.lastSeq !== undefined && data.seq <= this.lastSeq) {
          break
        }
        this.lastSeq = data.seq
        this.onEvent?.({
          seq: data.seq,
          type: data.type,
          text: data.text,
          tone: typeof data.tone === 'string' ? data.tone : null,
          player_id: typeof data.player_id === 'string' ? data.player_id : null,
          announcement: typeof data.announcement === 'string' ? data.announcement : null,
          subject_name: typeof data.subject_name === 'string' ? data.subject_name : null,
        })
        break
      case 'removed':
        this.markRemoved()
        break
      case 'welcome':
      case 'pong':
        break
      default:
        break
    }
  }
}
