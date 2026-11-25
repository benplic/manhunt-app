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

/** Sent once in `hello` so the server can tell iOS from web in its disconnect log. */
export type ClientInfo = {
  platform: 'ios' | 'web'
  app_version: string
  os_version: string
}

/** What the four-bar meter reads. See `socketMeter` for the mapping. */
export type SocketHealth = {
  /** Open and the server has said welcome. */
  connected: boolean
  /** Consecutive drops since the last stable connection. 0 while healthy. */
  failureStreak: number
  /** Epoch ms of the last message of any kind from the server, or null before the first. */
  lastMessageAt: number | null
}

/** A connection that lasts this long is "stable": the backoff and failure streak reset. */
export const STABLE_CONNECTION_MS = 10_000
/** Several triggers (online, visible, a close) at once collapse into one reconnect. */
export const RECONNECT_DEBOUNCE_MS = 300
/** The ping is 15 s, so a quiet socket this long is probably half-open. */
export const STALE_SOCKET_MS = 20_000
/** A fix older than this is not replayed after a reconnect. TODO: tune with playtest data. */
export const RESEND_FIX_MAX_AGE_MS = 60_000

function osVersionFromUserAgent(ua: string): string {
  const ios = /OS (\d+)[_.](\d+)[_\d]* like Mac OS X/.exec(ua)
  if (ios) {
    return `iOS ${ios[1]}.${ios[2]}`
  }
  const android = /Android (\d+(?:\.\d+)?)/.exec(ua)
  if (android) {
    return `Android ${android[1]}`
  }
  const windows = /Windows NT (\d+\.\d+)/.exec(ua)
  if (windows) {
    return `Windows NT ${windows[1]}`
  }
  const mac = /Mac OS X (\d+)[_.](\d+)/.exec(ua)
  if (mac) {
    return `macOS ${mac[1]}.${mac[2]}`
  }
  return ua ? 'other' : 'unknown'
}

/** Browser client block. No identifiers beyond coarse OS and the build version. */
export function browserClientInfo(): ClientInfo {
  const ua = typeof navigator === 'undefined' ? '' : navigator.userAgent
  return {
    platform: 'web',
    app_version: import.meta.env?.VITE_APP_VERSION ?? 'dev',
    os_version: osVersionFromUserAgent(ua),
  }
}

export type ConnectOptions = {
  url: string
  /** Static token; prefer getToken when the access token can rotate. */
  token?: string
  getToken?: () => string | null | undefined
  lastSeq?: number
  /** Defaults to `browserClientInfo()`. */
  client?: ClientInfo
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

/**
 * Browser WebSocket for `/v1/games/{id}/ws`. Hello first; ping every 15 s; backoff reconnect.
 * Also reconnects at once when the browser comes back online or the tab becomes visible,
 * and re-sends the latest location fix right after `welcome`.
 */
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
  private welcomed = false
  private openedAt: number | null = null
  private failureStreak = 0
  private lastMessageAt: number | null = null
  private stableTimer: ReturnType<typeof setTimeout> | null = null
  private triggerTimer: ReturnType<typeof setTimeout> | null = null
  private pendingTrigger: 'online' | 'visible' | null = null
  private lastFix: (PendingLocation & { at: number }) | null = null
  private listening = false
  lastSeq: number | undefined

  connect(options: ConnectOptions): void {
    this.disconnect()
    this.stopped = false
    this.reconnectDelayS = 1
    this.options = options
    this.failureStreak = 0
    this.lastMessageAt = null
    if (options.lastSeq !== undefined) {
      this.lastSeq = options.lastSeq
    }
    this.addTriggerListeners()
    this.openSocket()
  }

  /** Snapshot for the connection meter. Cheap enough to call every second. */
  health(): SocketHealth {
    return {
      connected: this.welcomed && this.socket?.readyState === WebSocket.OPEN,
      failureStreak: this.failureStreak,
      lastMessageAt: this.lastMessageAt,
    }
  }

  sendLocation(input: { lat: number; lon: number; accuracyM: number; flag?: string }): void {
    const payload: PendingLocation = {
      lat: input.lat,
      lon: input.lon,
      accuracyM: input.accuracyM,
      flag: input.flag ?? 'normal',
    }
    const now = Date.now()
    // Kept even while offline: the newest fix is what a reconnect re-sends.
    this.lastFix = { ...payload, at: now }
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
    this.welcomed = false
    this.clearPings()
    this.clearReconnect()
    this.clearTriggers()
    this.removeTriggerListeners()
    if (this.flushTimer !== null) {
      clearTimeout(this.flushTimer)
      this.flushTimer = null
    }
    this.pendingLocation = null
    this.lastFix = null
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
      const data: { token: string; last_seq?: number; client: ClientInfo } = {
        token: this.resolveToken(),
        client: this.options?.client ?? browserClientInfo(),
      }
      if (this.lastSeq !== undefined) {
        data.last_seq = this.lastSeq
      }
      ws.send(JSON.stringify({ type: 'hello', data }))
      this.openedAt = Date.now()
      this.startPings()
    }

    ws.onmessage = (event) => {
      if (this.socket !== ws) {
        return
      }
      this.lastMessageAt = Date.now()
      this.handleMessage(String(event.data))
    }

    ws.onclose = (event) => {
      // A socket we already replaced must not clear the new one's timers or schedule more.
      if (this.socket !== ws) {
        return
      }
      this.clearPings()
      this.clearStable()
      this.socket = null
      this.welcomed = false
      if (this.stopped) {
        return
      }
      if (event.code === 4403) {
        this.markRemoved()
        return
      }
      this.failureStreak += 1
      this.scheduleReconnect()
    }
  }

  /** Close the current socket without letting its `onclose` schedule a second reconnect. */
  private dropSocket(): void {
    const ws = this.socket
    this.socket = null
    this.welcomed = false
    this.clearPings()
    this.clearStable()
    if (!ws) {
      return
    }
    ws.onopen = null
    ws.onmessage = null
    ws.onclose = null
    ws.onerror = null
    try {
      ws.close()
    } catch {
      // TODO: log unexpected close failures once we have client telemetry.
    }
  }

  private addTriggerListeners(): void {
    if (this.listening || typeof window === 'undefined') {
      return
    }
    this.listening = true
    window.addEventListener('online', this.onOnline)
    document.addEventListener('visibilitychange', this.onVisibility)
  }

  private removeTriggerListeners(): void {
    if (!this.listening || typeof window === 'undefined') {
      return
    }
    this.listening = false
    window.removeEventListener('online', this.onOnline)
    document.removeEventListener('visibilitychange', this.onVisibility)
  }

  private onOnline = (): void => {
    this.requestReconnect('online')
  }

  private onVisibility = (): void => {
    if (document.visibilityState === 'visible') {
      this.requestReconnect('visible')
    }
  }

  /**
   * Coalesce reconnect triggers. A phone coming back from a lock screen fires `online` and
   * `visibilitychange` together, and a close can land in the same moment; one reconnect is
   * enough. `online` outranks `visible` because the old socket is certainly dead.
   */
  private requestReconnect(trigger: 'online' | 'visible'): void {
    if (this.stopped || !this.options) {
      return
    }
    if (trigger === 'online' || this.pendingTrigger === null) {
      this.pendingTrigger = trigger
    }
    if (this.triggerTimer !== null) {
      return
    }
    this.triggerTimer = setTimeout(() => {
      this.triggerTimer = null
      const reason = this.pendingTrigger
      this.pendingTrigger = null
      if (reason) {
        this.reconnectNow(reason)
      }
    }, RECONNECT_DEBOUNCE_MS)
  }

  private reconnectNow(reason: 'online' | 'visible'): void {
    // A host remove or membership close sets `stopped`; no trigger may undo that.
    if (this.stopped || !this.options) {
      return
    }
    const current = this.socket
    if (reason === 'visible' && current) {
      const connecting = current.readyState === WebSocket.CONNECTING
      const quiet = this.lastMessageAt === null || Date.now() - this.lastMessageAt > STALE_SOCKET_MS
      if (connecting || (this.welcomed && current.readyState === WebSocket.OPEN && !quiet)) {
        return
      }
    }
    this.clearReconnect()
    this.reconnectDelayS = 1
    this.dropSocket()
    this.openSocket()
  }

  private clearTriggers(): void {
    if (this.triggerTimer !== null) {
      clearTimeout(this.triggerTimer)
      this.triggerTimer = null
    }
    this.pendingTrigger = null
    this.clearStable()
  }

  private clearStable(): void {
    if (this.stableTimer !== null) {
      clearTimeout(this.stableTimer)
      this.stableTimer = null
    }
  }

  /** After a stable stretch the next drop starts the backoff over at 1 s. */
  private startStableTimer(): void {
    this.clearStable()
    this.stableTimer = setTimeout(() => {
      this.stableTimer = null
      this.failureStreak = 0
      this.reconnectDelayS = 1
    }, STABLE_CONNECTION_MS)
  }

  private resendLatestFix(): void {
    const fix = this.lastFix
    if (!fix || Date.now() - fix.at > RESEND_FIX_MAX_AGE_MS) {
      return
    }
    // The fix being re-sent is the newest one, so a throttled pending send is redundant.
    if (this.flushTimer !== null) {
      clearTimeout(this.flushTimer)
      this.flushTimer = null
    }
    this.pendingLocation = null
    this.flushLocation(fix)
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
    this.welcomed = false
    this.clearPings()
    this.clearReconnect()
    this.clearTriggers()
    this.removeTriggerListeners()
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
      // The server sends a view every second and answers every ping, so a welcomed socket
      // that has been silent this long is half-open: drop it and reconnect.
      // Also covers a socket that opened but never got `welcome` (hello lost on a dead path).
      const now = Date.now()
      const silent = this.welcomed
        ? this.lastMessageAt !== null && now - this.lastMessageAt > STALE_SOCKET_MS
        : this.openedAt !== null && now - this.openedAt > STALE_SOCKET_MS
      if (silent) {
        this.failureStreak += 1
        this.reconnectNow('online')
        return
      }
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
        this.welcomed = true
        this.openedAt = null
        this.startStableTimer()
        this.resendLatestFix()
        break
      case 'pong':
        break
      default:
        break
    }
  }
}
