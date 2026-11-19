import { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { GameSocket } from '../api/ws'
import { watchVisibleLocation } from '../geo/watchVisible'
import { ensureLeafletDefaultIcons } from '../map/leafletIcons'
import { pinsFromView } from '../map/pins'
import type { PlayerView } from '../api/types'
import './LiveMap.css'

type Props = {
  view: PlayerView
  socket: GameSocket
  qrToken: string | null
  note: string | null
  onLeave: () => void
  watchLocation?: typeof watchVisibleLocation
}

export function LiveMap({
  view,
  socket,
  qrToken,
  note,
  onLeave,
  watchLocation = watchVisibleLocation,
}: Props) {
  const mapEl = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<L.Map | null>(null)
  const markersRef = useRef<Map<string, L.Marker>>(new Map())
  const fittedRef = useRef(false)
  const [localNote, setLocalNote] = useState<string | null>(null)

  const pins = useMemo(() => pinsFromView(view), [view])

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
    }
  }, [])

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
    // Fit once when the first pins arrive so 1 Hz views do not fight pan/zoom.
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
    if (!map || pins.length === 0) {
      return
    }
    const bounds = L.latLngBounds(pins.map((p) => [p.lat, p.lon] as [number, number]))
    map.fitBounds(bounds.pad(0.35))
  }

  const alert = note ?? localNote

  return (
    <main className="live-map">
      <header>
        <div>
          <h1>Live map</h1>
          <p>
            {view.phase.replace('_', ' ')} · {view.join_code} · you are {view.you.role}
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
      <div className="map-frame" ref={mapEl} role="presentation" />
      {qrToken ? <p className="qr-note">QR token ready (scanner comes next)</p> : null}
      {alert ? (
        <p className="error" role="alert">
          {alert}
        </p>
      ) : null}
      <p className="hint">Keep this tab visible and the screen on for GPS.</p>
    </main>
  )
}
