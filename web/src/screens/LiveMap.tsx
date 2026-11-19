import { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { ApiError } from '../api/client'
import { endGame } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import type { GameSocket } from '../api/ws'
import { watchVisibleLocation } from '../geo/watchVisible'
import { formatClock } from '../map/clock'
import { ensureLeafletDefaultIcons } from '../map/leafletIcons'
import { pinsFromView } from '../map/pins'
import type { PlayerView } from '../api/types'
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

type Panel = 'map' | 'show' | 'scan'

function phaseLabel(phase: string): string {
  return phase.replaceAll('_', ' ')
}

function boundsMessage(view: PlayerView): string | null {
  const bounds = view.you.bounds
  if (!bounds || bounds.phase === 'inside') {
    return null
  }
  if (bounds.phase === 'countdown' && bounds.remaining_s != null) {
    return `Outside the play circle — ${bounds.remaining_s}s until auto-tag.`
  }
  if (bounds.phase === 'warning' || bounds.phase === 'countdown') {
    return 'Outside the play circle — walk back in.'
  }
  if (bounds.phase === 'penalized') {
    return 'Tagged out of bounds.'
  }
  return `Boundary: ${bounds.phase}`
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
  const arenaCircleRef = useRef<L.Circle | null>(null)
  const fittedRef = useRef(false)
  const [localNote, setLocalNote] = useState<string | null>(null)
  const [panel, setPanel] = useState<Panel>('map')
  const [ending, setEnding] = useState(false)

  const pins = useMemo(() => pinsFromView(view), [view])
  const isHider = view.you.role === 'hider'
  const isSeeker = view.you.role === 'seeker'
  const isHost = view.you.is_host
  const overlayOpen = panel !== 'map'
  const oobNote = boundsMessage(view)

  // Never leave the tag scanner open during head start (a claim in flight can
  // land the moment the phase flips to active and end the hunt instantly).
  useEffect(() => {
    if (view.phase === 'head_start' && panel === 'scan') {
      setPanel('map')
    }
  }, [view.phase, panel])

  const clockPrimary =
    view.phase === 'head_start'
      ? `Head start ${formatClock(view.phase_remaining_s)}`
      : `Hunt ${formatClock(view.time_limit_remaining_s)}`

  useEffect(() => {
    if (!mapEl.current || mapRef.current) {
      return
    }
    ensureLeafletDefaultIcons()
    const map = L.map(mapEl.current, { zoomControl: true }).setView([40.66, -73.96], 15)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap',
      maxZoom: 19,
    }).addTo(map)
    mapRef.current = map
    fittedRef.current = false
    return () => {
      map.remove()
      mapRef.current = null
      markersRef.current.clear()
      arenaCircleRef.current = null
    }
  }, [])

  // Keep the Leaflet container mounted under QR overlays; refresh size when returning.
  useEffect(() => {
    if (panel !== 'map') {
      return
    }
    const map = mapRef.current
    if (!map) {
      return
    }
    const id = window.setTimeout(() => map.invalidateSize(), 0)
    return () => window.clearTimeout(id)
  }, [panel])

  useEffect(() => {
    const map = mapRef.current
    if (!map) {
      return
    }
    const circle = view.arena?.boundary_circle
    if (!circle) {
      arenaCircleRef.current?.remove()
      arenaCircleRef.current = null
      return
    }
    const latLng: L.LatLngExpression = [circle.center.lat, circle.center.lon]
    if (!arenaCircleRef.current) {
      arenaCircleRef.current = L.circle(latLng, {
        radius: circle.radius_m,
        color: '#1a1a1a',
        weight: 2,
        fillColor: '#1a1a1a',
        fillOpacity: 0.06,
      }).addTo(map)
    } else {
      arenaCircleRef.current.setLatLng(latLng)
      arenaCircleRef.current.setRadius(circle.radius_m)
    }
  }, [view.arena])

  useEffect(() => {
    const map = mapRef.current
    if (!map) {
      return
    }
    const seen = new Set<string>()
    for (const pin of pins) {
      seen.add(pin.playerId)
      let marker = markersRef.current.get(pin.playerId)
      const label = `${pin.displayName} (${pin.role})${pin.isYou ? ' · you' : ''}`
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
    if (!fittedRef.current && pins.length > 0) {
      const bounds = L.latLngBounds(pins.map((p) => [p.lat, p.lon] as [number, number]))
      map.fitBounds(bounds.pad(0.35))
      fittedRef.current = true
    }
  }, [pins])

  useEffect(() => {
    const stopWatch = watchLocation({
      onFix: (fix) => {
        socket.sendLocation({
          lat: fix.lat,
          lon: fix.lon,
          accuracyM: fix.accuracyM,
        })
      },
      onError: (message) => setLocalNote(message),
    })
    return () => stopWatch()
  }, [socket, watchLocation])

  function recenter() {
    const map = mapRef.current
    if (!map) {
      return
    }
    const circle = view.arena?.boundary_circle
    if (circle) {
      map.fitBounds(
        L.latLng(circle.center.lat, circle.center.lon).toBounds(circle.radius_m * 2.2),
      )
      return
    }
    if (pins.length === 0) {
      return
    }
    const bounds = L.latLngBounds(pins.map((p) => [p.lat, p.lon] as [number, number]))
    map.fitBounds(bounds.pad(0.35))
  }

  async function onEnd() {
    setEnding(true)
    setLocalNote(null)
    try {
      const ended = await withAuthRetry((token) => endGame({ token, gameId: view.game_id }))
      onView(ended)
    } catch (err) {
      if (err instanceof SessionExpiredError) {
        onSignedOut()
        return
      }
      setLocalNote(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setEnding(false)
    }
  }

  const alert = oobNote ?? note ?? localNote

  return (
    <main className={`live-map${overlayOpen ? ' live-map--overlay' : ''}`}>
      <header>
        <div>
          <h1>Live map</h1>
          <p>
            {phaseLabel(view.phase)} · {view.join_code} · you are {view.you.role}
          </p>
        </div>
        <div className="actions">
          <button type="button" className="secondary" onClick={recenter}>
            Recenter
          </button>
          <button type="button" onClick={onLeave}>
            Leave
          </button>
        </div>
      </header>

      {!overlayOpen ? (
        <div className="hud" aria-live="polite">
          <span className="hud-clock">{clockPrimary}</span>
          {view.phase === 'head_start' ? (
            <span className="hud-sub">Hunt clock {formatClock(view.time_limit_remaining_s)}</span>
          ) : (
            <span className="hud-sub">Elapsed {formatClock(view.game_elapsed_s)}</span>
          )}
        </div>
      ) : null}

      {/* Map stays mounted so Show/Scan overlays do not orphan the Leaflet instance. */}
      <div
        className={`map-frame${overlayOpen ? ' map-frame--hidden' : ''}`}
        ref={mapEl}
        role="presentation"
        aria-hidden={overlayOpen}
      />
      {!overlayOpen ? (
        <>
          <div className="toolbar">
            {isHider ? (
              <button type="button" disabled={!qrToken} onClick={() => setPanel('show')}>
                Show QR
              </button>
            ) : null}
            {isSeeker && view.phase === 'active' ? (
              <button type="button" onClick={() => setPanel('scan')}>
                Scan QR
              </button>
            ) : null}
            {isSeeker && view.phase === 'head_start' ? (
              <p className="qr-note">Seekers cannot tag until head start ends.</p>
            ) : null}
            {isHost ? (
              <button
                type="button"
                className="danger"
                disabled={ending}
                onClick={() => void onEnd()}
              >
                {ending ? 'Ending…' : 'End hunt'}
              </button>
            ) : null}
          </div>
          {isHider && !qrToken ? (
            <p className="qr-note">Waiting for a tag QR from the server…</p>
          ) : null}
          {alert ? (
            <p className={`error${oobNote ? ' error--oob' : ''}`} role="alert">
              {alert}
            </p>
          ) : null}
          <p className="hint">
            Stay inside the dark circle. Keep this tab visible and the screen on for GPS.
          </p>
        </>
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
            onClose={() => setPanel('map')}
            onTagged={() => {
              setLocalNote('Tag accepted.')
              setPanel('map')
            }}
            onSignedOut={onSignedOut}
          />
        </div>
      ) : null}
    </main>
  )
}
