import { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { apiBaseUrl } from '../api/config'
import { GameSocket, wsUrlForGame } from '../api/ws'
import { watchVisibleLocation } from '../geo/watchVisible'
import { pinsFromView } from '../map/pins'
import type { PlayerView } from '../api/types'
import { loadSession } from '../auth/storage'
import './LiveMap.css'

type Props = {
  view: PlayerView
  onView: (view: PlayerView) => void
  onLeave: () => void
  /** Optional injectables for tests. */
  createSocket?: () => GameSocket
  watchLocation?: typeof watchVisibleLocation
}

export function LiveMap({
  view,
  onView,
  onLeave,
  createSocket = () => new GameSocket(),
  watchLocation = watchVisibleLocation,
}: Props) {
  const mapEl = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<L.Map | null>(null)
  const markersRef = useRef<Map<string, L.Marker>>(new Map())
  const socketRef = useRef<GameSocket | null>(null)
  const [qrToken, setQrToken] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)
  const viewRef = useRef(view)
  viewRef.current = view

  const pins = useMemo(() => pinsFromView(view), [view])

  useEffect(() => {
    if (!mapEl.current || mapRef.current) {
      return
    }
    const map = L.map(mapEl.current, { zoomControl: true }).setView([40.66, -73.96], 15)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap',
      maxZoom: 19,
    }).addTo(map)
    mapRef.current = map
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
        markersRef.current.set(pin.playerId, marker)
      } else {
        marker.setLatLng([pin.lat, pin.lon])
      }
      marker.bindPopup(label)
      if (pin.isYou) {
        marker.openPopup()
      }
    }
    for (const [id, marker] of markersRef.current) {
      if (!seen.has(id)) {
        marker.remove()
        markersRef.current.delete(id)
      }
    }
    if (pins.length > 0) {
      const bounds = L.latLngBounds(pins.map((p) => [p.lat, p.lon] as [number, number]))
      map.fitBounds(bounds.pad(0.35))
    }
  }, [pins])

  useEffect(() => {
    const session = loadSession()
    if (!session) {
      return
    }
    const socket = createSocket()
    socketRef.current = socket
    socket.onView = (next) => onView(next)
    socket.onQr = (token) => setQrToken(token)
    socket.onError = (err) => setNote(err.message)
    socket.connect({
      url: wsUrlForGame(apiBaseUrl(), view.game_id),
      token: session.accessToken,
      lastSeq: socket.lastSeq,
    })

    const stopWatch = watchLocation({
      onFix: (fix) => {
        socket.sendLocation({
          lat: fix.lat,
          lon: fix.lon,
          accuracyM: fix.accuracyM,
        })
      },
      onError: (message) => setNote(message),
    })

    return () => {
      stopWatch()
      socket.disconnect()
      socketRef.current = null
    }
    // Reconnect only when the game id changes; view updates arrive over the socket.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view.game_id])

  return (
    <main className="live-map">
      <header>
        <div>
          <h1>Live map</h1>
          <p>
            {view.phase.replace('_', ' ')} · {view.join_code} · you are {view.you.role}
          </p>
        </div>
        <button type="button" onClick={onLeave}>
          Leave
        </button>
      </header>
      <div className="map-frame" ref={mapEl} role="presentation" />
      {qrToken ? <p className="qr-note">QR token ready (scanner comes next)</p> : null}
      {note ? (
        <p className="error" role="alert">
          {note}
        </p>
      ) : null}
      <p className="hint">Keep this tab visible and the screen on for GPS.</p>
    </main>
  )
}
