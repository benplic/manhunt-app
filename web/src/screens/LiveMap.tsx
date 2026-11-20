import { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { ApiError } from '../api/client'
import { endGame, pauseGame, resumeGame, undoLastTag } from '../api/games'
import { SUPPORT_EMAIL } from '../api/legal'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { GameSocket } from '../api/ws'
import { startLivePresence } from '../geo/presence'
import { requestHuntWakeLock } from '../geo/wakeLock'
import { watchVisibleLocation } from '../geo/watchVisible'
import type { GeoFix } from '../geo/watchVisible'
import {
  arenaIdentityKey,
  centroid,
  resolvePlayBoundary,
} from '../map/arenaBoundary'
import { fitArenaOnce, recenterOnArena } from '../map/arenaCamera'
import { formatClock } from '../map/clock'
import { ensureLeafletDefaultIcons } from '../map/leafletIcons'
import { pinsFromView } from '../map/pins'
import { revealsFromView } from '../map/reveals'
import {
  emphasizeSpawnFromView,
  visibleZones,
  zoneStyle,
} from '../map/zones'
import { blockPlayer, reportMailto } from '../social/blockList'
import type { ArenaZone, PlayerView } from '../api/types'
import { QrScan } from './QrScan'
import { QrShow } from './QrShow'
import './LiveMap.css'

type Props = {
  view: PlayerView
  socket: GameSocket
  qrToken: string | null
  note: string | null
  onView: (view: PlayerView) => void
  onLeave: () => void
  onSignedOut: () => void
  watchLocation?: typeof watchVisibleLocation
}

type Panel = 'map' | 'show' | 'scan' | 'board'

function phaseLabel(phase: string): string {
  return phase.replaceAll('_', ' ')
}

function boundsMessage(view: PlayerView): string | null {
  const bounds = view.you.bounds
  if (!bounds || bounds.phase === 'inside') {
    return null
  }
  if (view.phase === 'head_start' && bounds.phase === 'warning') {
    return 'Outside the play area — walk in before the hunt starts.'
  }
  if (bounds.phase === 'countdown' && bounds.remaining_s != null) {
    return `Outside the play area — ${bounds.remaining_s}s until auto-tag.`
  }
  if (bounds.phase === 'warning' || bounds.phase === 'countdown') {
    return 'Outside the play area — walk back in.'
  }
  if (bounds.phase === 'penalized') {
    return 'Tagged out of bounds.'
  }
  return `Boundary: ${bounds.phase}`
}

function darkMessage(view: PlayerView): string | null {
  if (view.you.status === 'signal_lost') {
    return 'You went dark. Keep this tab visible and the screen on.'
  }
  return null
}

type ZonePathOpts = {
  color: string
  weight: number
  fillColor: string
  fillOpacity: number
  opacity: number
}

/** Create or update a circle/polygon zone layer; returns the live Leaflet path. */
function upsertZoneLayer(
  map: L.Map,
  existing: L.Circle | L.Polygon | undefined,
  zone: ArenaZone,
  pathOpts: ZonePathOpts,
): L.Circle | L.Polygon {
  if (zone.shape.type === 'circle') {
    const latLng: L.LatLngExpression = [zone.shape.center.lat, zone.shape.center.lon]
    if (existing && existing instanceof L.Circle) {
      existing.setLatLng(latLng)
      existing.setRadius(zone.shape.radius_m)
      existing.setStyle(pathOpts)
      return existing
    }
    return L.circle(latLng, { radius: zone.shape.radius_m, ...pathOpts }).addTo(map)
  }
  const latLngs = zone.shape.vertices.map((v) => [v.lat, v.lon] as [number, number])
  if (existing && !(existing instanceof L.Circle)) {
    existing.setLatLngs(latLngs)
    existing.setStyle(pathOpts)
    return existing
  }
  // Shape kind changed (circle → polygon): caller removes `existing`.
  return L.polygon(latLngs, pathOpts).addTo(map)
}

export function LiveMap({
  view,
  socket,
  qrToken,
  note,
  onView,
  onLeave,
  onSignedOut,
  watchLocation = watchVisibleLocation,
}: Props) {
  const mapEl = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<L.Map | null>(null)
  const markersRef = useRef<Map<string, L.Marker>>(new Map())
  const revealRef = useRef<Map<string, L.Circle>>(new Map())
  const arenaCircleRef = useRef<L.Circle | null>(null)
  const arenaPolygonRef = useRef<L.Polygon | null>(null)
  const zoneLayersRef = useRef<Map<string, L.Circle | L.Polygon>>(new Map())
  /** Last arenaKey we framed — re-fit only when the play area identity changes. */
  const fittedArenaKeyRef = useRef<string>('')
  const [localNote, setLocalNote] = useState<string | null>(null)
  const [accuracyM, setAccuracyM] = useState<number | null>(null)
  const [panel, setPanel] = useState<Panel>('map')
  const [busyHost, setBusyHost] = useState(false)
  const [toast, setToast] = useState<string | null>(null)

  const pins = useMemo(() => pinsFromView(view), [view])
  const reveals = useMemo(() => revealsFromView(view), [view])
  const playBoundary = useMemo(() => resolvePlayBoundary(view.arena ?? null), [view.arena])
  const arenaKey = arenaIdentityKey(playBoundary)
  const emphasizeSpawn = emphasizeSpawnFromView(view)
  const lockdown = (view.you.effects ?? []).includes('lockdown')
  const zonesOnMap = useMemo(
    () =>
      visibleZones({
        arenaZones: view.arena?.zones ?? [],
        spawnLockZones: view.spawn_lock?.zones ?? [],
        phase: view.phase,
        emphasizeSpawn,
      }),
    [view.arena?.zones, view.spawn_lock?.zones, view.phase, emphasizeSpawn],
  )
  const banners = view.banners ?? []
  const isHider = view.you.role === 'hider'
  const isSeeker = view.you.role === 'seeker'
  const isHost = view.you.is_host
  const overlayOpen = panel !== 'map'
  const oobNote = boundsMessage(view)
  const wentDark = darkMessage(view)
  const pingLeft = view.timers?.next_reveal_in_s

  // Never leave the tag scanner open during head start.
  useEffect(() => {
    if (view.phase === 'head_start' && panel === 'scan') {
      setPanel('map')
    }
  }, [view.phase, panel])

  useEffect(() => {
    let release: (() => void) | undefined
    void requestHuntWakeLock().then((stop) => {
      release = stop
    })
    return () => release?.()
  }, [])

  const clockPrimary =
    view.phase === 'paused'
      ? 'Paused'
      : view.phase === 'head_start'
        ? `Head start ${formatClock(view.phase_remaining_s)}`
        : `Hunt ${formatClock(view.time_limit_remaining_s)}`

  useEffect(() => {
    if (!mapEl.current || mapRef.current) {
      return
    }
    ensureLeafletDefaultIcons()
    // Default zoom controls stay off; pinch / two-finger pan are unbounded.
    const map = L.map(mapEl.current, {
      zoomControl: true,
      attributionControl: false,
      // Keep gestures on the map, not the page underneath.
      dragging: true,
      touchZoom: true,
      scrollWheelZoom: true,
      doubleClickZoom: true,
      boxZoom: true,
    }).setView([40.66, -73.96], 15)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap',
      maxZoom: 19,
    }).addTo(map)
    mapRef.current = map
    fittedArenaKeyRef.current = ''
    return () => {
      map.remove()
      mapRef.current = null
      markersRef.current.clear()
      revealRef.current.clear()
      zoneLayersRef.current.clear()
      arenaCircleRef.current = null
      arenaPolygonRef.current = null
      fittedArenaKeyRef.current = ''
    }
  }, [])

  // Keep Leaflet sized when chrome grows (head start → active banners/dock)
  // or when the mobile URL bar shows/hides. A zero-size frame paints black.
  useEffect(() => {
    const map = mapRef.current
    const frame = mapEl.current
    if (!map || !frame) {
      return
    }
    const refresh = () => {
      if (panel !== 'map') {
        return
      }
      map.invalidateSize({ animate: false })
    }
    const id = window.setTimeout(refresh, 0)
    const delayed = window.setTimeout(refresh, 120)
    const observer =
      typeof ResizeObserver !== 'undefined' ? new ResizeObserver(() => refresh()) : null
    observer?.observe(frame)
    window.addEventListener('resize', refresh)
    window.addEventListener('orientationchange', refresh)
    return () => {
      window.clearTimeout(id)
      window.clearTimeout(delayed)
      observer?.disconnect()
      window.removeEventListener('resize', refresh)
      window.removeEventListener('orientationchange', refresh)
    }
  }, [panel, view.phase])

  useEffect(() => {
    const map = mapRef.current
    if (!map) {
      return
    }
    // arenaKey is the stable identity; view.arena object identity changes every tick.
    if (!playBoundary || !arenaKey) {
      arenaCircleRef.current?.remove()
      arenaCircleRef.current = null
      arenaPolygonRef.current?.remove()
      arenaPolygonRef.current = null
      fittedArenaKeyRef.current = ''
      return
    }
    const style = {
      color: '#f0c75e',
      weight: 2,
      fillColor: '#111',
      fillOpacity: 0.18,
    }
    if (playBoundary.kind === 'circle') {
      arenaPolygonRef.current?.remove()
      arenaPolygonRef.current = null
      const latLng: L.LatLngExpression = [
        playBoundary.circle.center.lat,
        playBoundary.circle.center.lon,
      ]
      if (!arenaCircleRef.current) {
        arenaCircleRef.current = L.circle(latLng, {
          radius: playBoundary.circle.radius_m,
          ...style,
        }).addTo(map)
      } else {
        arenaCircleRef.current.setLatLng(latLng)
        arenaCircleRef.current.setRadius(playBoundary.circle.radius_m)
      }
    } else {
      arenaCircleRef.current?.remove()
      arenaCircleRef.current = null
      const latLngs = playBoundary.vertices.map(
        (v) => [v.lat, v.lon] as [number, number],
      )
      if (!arenaPolygonRef.current) {
        arenaPolygonRef.current = L.polygon(latLngs, style).addTo(map)
      } else {
        arenaPolygonRef.current.setLatLngs(latLngs)
      }
    }
    // Frame once per arena identity. Re-fitting every WS tick snapped pan/zoom.
    if (fittedArenaKeyRef.current !== arenaKey) {
      fitArenaOnce(map, playBoundary, L)
      fittedArenaKeyRef.current = arenaKey
      window.setTimeout(() => map.invalidateSize(), 0)
    }
  }, [arenaKey, playBoundary])

  useEffect(() => {
    const map = mapRef.current
    if (!map) {
      return
    }
    const seen = new Set<string>()
    for (const zone of zonesOnMap) {
      seen.add(zone.id)
      const style = zoneStyle(zone.kind, { emphasizeSpawn, lockdown })
      const pathOpts = {
        color: style.color,
        weight: style.weight,
        fillColor: style.fillColor,
        fillOpacity: style.fillOpacity,
        opacity: style.strokeOpacity,
      }
      const existing = zoneLayersRef.current.get(zone.id)
      const next = upsertZoneLayer(map, existing, zone, pathOpts)
      if (next !== existing) {
        existing?.remove()
        zoneLayersRef.current.set(zone.id, next)
      }
    }
    for (const [id, layer] of zoneLayersRef.current) {
      if (!seen.has(id)) {
        layer.remove()
        zoneLayersRef.current.delete(id)
      }
    }
  }, [zonesOnMap, emphasizeSpawn, lockdown])

  useEffect(() => {
    const map = mapRef.current
    if (!map) {
      return
    }
    const seen = new Set<string>()
    for (const pin of reveals) {
      seen.add(pin.reveal_id)
      let circle = revealRef.current.get(pin.reveal_id)
      const latLng: L.LatLngExpression = [pin.lat, pin.lon]
      if (!circle) {
        circle = L.circle(latLng, {
          radius: pin.radius_m,
          color: '#6ea8fe',
          weight: 1,
          fillColor: '#6ea8fe',
          fillOpacity: 0.22,
        }).addTo(map)
        circle.bindPopup(`${pin.display_name} · ping`)
        revealRef.current.set(pin.reveal_id, circle)
      } else {
        circle.setLatLng(latLng)
        circle.setRadius(pin.radius_m)
      }
    }
    for (const [id, circle] of revealRef.current) {
      if (!seen.has(id)) {
        circle.remove()
        revealRef.current.delete(id)
      }
    }
  }, [reveals])

  useEffect(() => {
    const map = mapRef.current
    if (!map) {
      return
    }
    const seen = new Set<string>()
    for (const pin of pins) {
      seen.add(pin.playerId)
      let marker = markersRef.current.get(pin.playerId)
      const label = `${pin.displayName} (${pin.role})${pin.isYou ? ' · you' : ''}${
        pin.status === 'signal_lost' ? ' · dark' : ''
      }`
      if (!marker) {
        marker = L.marker([pin.lat, pin.lon]).addTo(map)
        marker.bindPopup(label)
        markersRef.current.set(pin.playerId, marker)
      } else {
        marker.setLatLng([pin.lat, pin.lon])
        marker.setPopupContent(label)
      }
    }
    for (const [id, marker] of markersRef.current) {
      if (!seen.has(id)) {
        marker.remove()
        markersRef.current.delete(id)
      }
    }
  }, [pins])

  useEffect(() => {
    // Mac/desktop often never gets watchPosition. Seed the play-area center so
    // the host hider does not go dark after classic silence while desk-testing.
    let seedFix: GeoFix | null = null
    if (playBoundary?.kind === 'circle') {
      seedFix = {
        lat: playBoundary.circle.center.lat,
        lon: playBoundary.circle.center.lon,
        accuracyM: 12,
      }
    } else if (playBoundary?.kind === 'polygon') {
      const mid = centroid(playBoundary.vertices)
      if (mid) {
        seedFix = { lat: mid.lat, lon: mid.lon, accuracyM: 12 }
      }
    }
    const stop = startLivePresence({
      seedFix,
      watchLocation,
      onFix: (fix) => {
        setAccuracyM(fix.accuracyM)
        socket.sendLocation({
          lat: fix.lat,
          lon: fix.lon,
          accuracyM: fix.accuracyM,
        })
      },
      onError: (message) => setLocalNote(message),
    })
    return () => stop()
  }, [socket, watchLocation, arenaKey])

  function recenter() {
    const map = mapRef.current
    if (!map) {
      return
    }
    if (playBoundary) {
      recenterOnArena(map, playBoundary, L)
      return
    }
    if (pins.length === 0) {
      return
    }
    const bounds = L.latLngBounds(pins.map((p) => [p.lat, p.lon] as [number, number]))
    map.fitBounds(bounds.pad(0.35))
  }

  async function runHost(action: () => Promise<PlayerView>) {
    setBusyHost(true)
    setLocalNote(null)
    try {
      const next = await action()
      onView(next)
    } catch (err) {
      if (err instanceof SessionExpiredError) {
        onSignedOut()
        return
      }
      setLocalNote(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusyHost(false)
    }
  }

  function onBlock(playerId: string, displayName: string) {
    blockPlayer(playerId, displayName)
    setToast(`${displayName} blocked on this device.`)
    setPanel('map')
  }

  function onReport(playerId: string, displayName: string) {
    window.location.href = reportMailto({
      gameId: view.game_id,
      playerId,
      displayName,
      supportEmail: SUPPORT_EMAIL,
    })
  }

  // Filter socket "too fast" noise out of the main alert strip.
  const socketNote =
    note && note.toLowerCase().includes('too fast') ? null : note
  const alert = wentDark ?? oobNote ?? socketNote ?? localNote

  const ranked = [...view.players].sort(
    (a, b) => (b.points_earned ?? b.points ?? 0) - (a.points_earned ?? a.points ?? 0),
  )

  return (
    <main className={`live-map${overlayOpen ? ' live-map--overlay' : ''}`}>
      <header className="top-bar">
        <div className="identity">
          <p className="eyebrow">
            {phaseLabel(view.phase)} · {view.join_code}
          </p>
          <p className="role-pill">{view.you.role}</p>
        </div>
        <div className="actions chip-row">
          <button type="button" className="chip" onClick={recenter}>
            Recenter
          </button>
          <button type="button" className="chip" onClick={() => setPanel('board')}>
            Scores
          </button>
          <button type="button" className="chip chip--accent" onClick={onLeave}>
            Leave
          </button>
        </div>
      </header>

      {!overlayOpen ? (
        <div className="hud" aria-live="polite">
          <span className="hud-clock">{clockPrimary}</span>
          {pingLeft != null ? (
            <span className="hud-sub">Ping {formatClock(pingLeft)}</span>
          ) : null}
          <span className="hud-sub">{view.you.points ?? 0} pts</span>
          {accuracyM != null ? (
            <span className={`hud-sub${accuracyM > 30 ? ' hud-sub--warn' : ''}`}>
              GPS ±{Math.round(accuracyM)} m
            </span>
          ) : (
            <span className="hud-sub hud-sub--warn">GPS…</span>
          )}
          {view.you.hint ? <span className="hud-hint">{view.you.hint}</span> : null}
        </div>
      ) : null}

      {banners.length > 0 && !overlayOpen ? (
        <div className="banners">
          {banners.map((banner) => (
            <p key={banner.banner_id} className={`banner banner--${banner.tone}`}>
              <strong>{banner.title}</strong>
              {banner.detail ? ` — ${banner.detail}` : ''}
            </p>
          ))}
        </div>
      ) : null}

      <div
        className={`map-frame${overlayOpen ? ' map-frame--hidden' : ''}`}
        ref={mapEl}
        role="presentation"
        aria-hidden={overlayOpen}
      />

      {!overlayOpen ? (
        <footer className="bottom-stack">
          {alert ? (
            <p className={`alert${oobNote || wentDark ? ' alert--warn' : ''}`} role="alert">
              {alert}
            </p>
          ) : null}
          {toast ? (
            <p className="toast" role="status">
              {toast}
            </p>
          ) : null}
          <div className="dock">
            {isHider ? (
              <button type="button" className="chip chip--accent" disabled={!qrToken} onClick={() => setPanel('show')}>
                Show tag
              </button>
            ) : null}
            {isSeeker && view.phase === 'active' ? (
              <button type="button" className="chip chip--accent" onClick={() => setPanel('scan')}>
                Scan tag
              </button>
            ) : null}
            {isSeeker && view.phase === 'head_start' ? (
              <p className="dock-note">Seekers cannot tag until head start ends.</p>
            ) : null}
            {isHider && !qrToken ? (
              <p className="dock-note">Waiting for a tag QR from the server…</p>
            ) : null}
          </div>
          {isHost ? (
            <div className="host-strip" aria-label="Host controls">
              <p className="host-label">Host</p>
              <div className="chip-row">
                {view.phase === 'paused' ? (
                  <button
                    type="button"
                    className="chip"
                    disabled={busyHost}
                    onClick={() =>
                      void runHost(() =>
                        withAuthRetry((token) => resumeGame({ token, gameId: view.game_id })),
                      )
                    }
                  >
                    Resume
                  </button>
                ) : (
                  <button
                    type="button"
                    className="chip"
                    disabled={busyHost}
                    onClick={() =>
                      void runHost(() =>
                        withAuthRetry((token) => pauseGame({ token, gameId: view.game_id })),
                      )
                    }
                  >
                    Pause
                  </button>
                )}
                <button
                  type="button"
                  className="chip"
                  disabled={busyHost}
                  onClick={() =>
                    void runHost(() =>
                      withAuthRetry((token) => undoLastTag({ token, gameId: view.game_id })),
                    )
                  }
                >
                  Undo tag
                </button>
                <button
                  type="button"
                  className="chip chip--danger"
                  disabled={busyHost}
                  onClick={() =>
                    void runHost(() =>
                      withAuthRetry((token) => endGame({ token, gameId: view.game_id })),
                    )
                  }
                >
                  End hunt
                </button>
              </div>
            </div>
          ) : null}
          <p className="hint">Keep this tab visible and the screen on. Stay inside the yellow play area.</p>
        </footer>
      ) : null}

      {panel === 'show' && qrToken ? (
        <div className="qr-overlay">
          <QrShow token={qrToken} onClose={() => setPanel('map')} />
        </div>
      ) : null}
      {panel === 'scan' ? (
        <div className="qr-overlay">
          <QrScan
            gameId={view.game_id}
            accuracyM={accuracyM}
            onClose={() => setPanel('map')}
            onTagged={() => {
              setLocalNote('Tag accepted.')
              setToast('Tag accepted.')
              setPanel('map')
            }}
            onSignedOut={onSignedOut}
          />
        </div>
      ) : null}
      {panel === 'board' ? (
        <div className="qr-overlay board">
          <header className="top-bar">
            <h1>Leaderboard</h1>
            <button type="button" className="chip" onClick={() => setPanel('map')}>
              Close
            </button>
          </header>
          <ul>
            {ranked.map((player) => (
              <li key={player.player_id}>
                <div>
                  <strong>{player.display_name}</strong>
                  <span>
                    {player.role} · {player.points_earned ?? player.points ?? 0} pts
                  </span>
                </div>
                {player.player_id !== view.you.player_id ? (
                  <div className="chip-row">
                    <button
                      type="button"
                      className="chip"
                      onClick={() => onBlock(player.player_id, player.display_name)}
                    >
                      Block
                    </button>
                    <button
                      type="button"
                      className="chip"
                      onClick={() => onReport(player.player_id, player.display_name)}
                    >
                      Report
                    </button>
                  </div>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </main>
  )
}
