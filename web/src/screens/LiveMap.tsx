import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { ApiError } from '../api/client'
import {
  endGame,
  pauseGame,
  purchasePowerUp,
  resumeGame,
  tauntGame,
  undoLastTag,
} from '../api/games'
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
import { hintLine } from '../game/hintLine'
import { pointInPlayArea } from '../map/pointInPlayArea'
import { glidePoint, PIN_GLIDE_MS } from '../map/pinGlide'
import { useAlert } from '../game/useAlert'
import { newRevealIds } from '../map/pingFlash'
import {
  chipIsTappable,
  chipShowsDenialOnTap,
  decide,
  denialMessage,
  requiresMapPoint,
  requiresPlayerTarget,
  requiresTarget,
  requiresZoneTarget,
  type PurchaseRequest,
} from '../game/powerUpRules'
import { fitArenaOnce, recenterOnArena } from '../map/arenaCamera'
import { formatClock } from '../map/clock'
import { ensureLeafletDefaultIcons } from '../map/leafletIcons'
import { pinsFromView } from '../map/pins'
import { revealsFromView } from '../map/reveals'
import { textPopup } from '../map/textPopup'
import {
  emphasizeSpawnFromView,
  visibleZones,
  zoneStyle,
} from '../map/zones'
import { ConfirmDialog } from '../game/ConfirmDialog'
import { Leaderboard } from '../components/Leaderboard'
import { blockPlayer, displayNameFor, reportMailto } from '../social/blockList'
import type { ActiveEffect, ArenaZone, Banner, PlayerView } from '../api/types'
import { EventLog } from './EventLog'
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
  /** Safety gate is up. Do not seed or send a position until the player continues. */
  holdPresence?: boolean
}

type Panel = 'map' | 'show' | 'scan' | 'board' | 'log'

type PowerPick =
  | null
  | { step: 'map'; powerId: string }
  | { step: 'rescue'; powerId: string }
  | { step: 'zone'; powerId: string }
  | { step: 'zone_point'; powerId: string; zoneId: string }

function powerUpRequest(view: PlayerView, row: { id: string; cost: number; role: string; available: boolean }): PurchaseRequest {
  const cooldowns = view.you.cooldowns ?? {}
  return {
    balance: view.you.points ?? 0,
    cost: row.cost,
    cooldownRemaining: cooldowns[row.id] ?? 0,
    phase: view.phase as PurchaseRequest['phase'],
    role: view.you.role,
    requiredRole: row.role,
    status: view.you.status as PurchaseRequest['status'],
    requiresTarget: requiresTarget(row.id),
    hasTarget: false,
    available: row.available,
  }
}

function rescueCandidates(view: PlayerView) {
  return (view.players ?? []).filter(
    (p) =>
      p.player_id !== view.you.player_id &&
      (p.status === 'eliminated' || (p.role === 'seeker' && p.status === 'active')),
  )
}

function phaseLabel(phase: string): string {
  return phase.replaceAll('_', ' ')
}

/** HUD copy for a timed effect. Shield always names the owner for seekers. */
export function effectHudLine(effect: ActiveEffect, youId: string): string {
  const clock = formatClock(effect.remaining_s)
  const title = effect.type.replaceAll('_', ' ')
  const titled = title.charAt(0).toUpperCase() + title.slice(1)
  if (effect.owner_id === youId) {
    return `${titled} ${clock}`
  }
  const name = displayNameFor(effect.owner_id, effect.display_name || 'Player')
  return `${titled} · ${name} · ${clock}`
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

/** Safety and danger banners are one-off news. The rest describe a state that lasts. */
function isAlertBanner(banner: Banner): boolean {
  return banner.tone === 'safety' || banner.tone === 'danger'
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
  holdPresence = false,
}: Props) {
  const mapEl = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<L.Map | null>(null)
  const markersRef = useRef<Map<string, L.Marker>>(new Map())
  const revealRef = useRef<Map<string, L.Circle>>(new Map())
  const arenaCircleRef = useRef<L.Circle | null>(null)
  const shrinkPreviewRef = useRef<L.Circle | null>(null)
  const arenaPolygonRef = useRef<L.Polygon | null>(null)
  const pinAnimRef = useRef<Map<string, { from: { lat: number; lon: number }; started: number }>>(
    new Map(),
  )
  const pinRafRef = useRef<number | null>(null)
  const prevRevealsRef = useRef(view.reveals)
  const zoneLayersRef = useRef<Map<string, L.Circle | L.Polygon>>(new Map())
  /** Last arenaKey we framed — re-fit only when the play area identity changes. */
  const fittedArenaKeyRef = useRef<string>('')
  // An object, not a string, so the same message set twice is two distinct alerts.
  const [localNoteState, setLocalNoteState] = useState<{ id: number; text: string } | null>(null)
  const localNoteSeq = useRef(0)
  const setLocalNote = useCallback((text: string | null) => {
    localNoteSeq.current += 1
    setLocalNoteState(text ? { id: localNoteSeq.current, text } : null)
  }, [])
  const [accuracyM, setAccuracyM] = useState<number | null>(null)
  const [panel, setPanel] = useState<Panel>('map')
  const [busyHost, setBusyHost] = useState(false)
  const [toast, setToast] = useState<string | null>(null)
  const [busyDock, setBusyDock] = useState(false)
  const [powerPick, setPowerPick] = useState<PowerPick>(null)
  // The slot's clock stops while Scores or Log covers the map, so nothing is used up unseen.
  const { shown: shownAlert, enqueue: enqueueAlert } = useAlert({ paused: panel !== 'map' })
  /** Banner ids already queued, so a banner that stays in the view alerts only once. */
  const seenBannerIdsRef = useRef<Set<string>>(new Set())
  const [pendingLeave, setPendingLeave] = useState(false)
  const [pendingBlock, setPendingBlock] = useState<{ id: string; name: string } | null>(null)
  /** Bumped when the local block list changes so leaderboard names re-mask. */
  const [blockRevision, setBlockRevision] = useState(0)

  const pins = useMemo(() => pinsFromView(view), [view, blockRevision])
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
  const isHider = view.you.role === 'hider'
  const isSeeker = view.you.role === 'seeker'
  const isHost = view.you.is_host
  const overlayOpen = panel !== 'map'
  const oobNote = boundsMessage(view)
  const wentDark = darkMessage(view)
  const pingLeft = view.timers?.next_reveal_in_s
  // Hiders only. Seekers keep the existing Ping line for when they are exposed.
  const seekerPingLeft = isHider ? view.timers?.next_seeker_reveal_in_s : null
  const zoneTimer = view.timers?.zone
  const powerUps = useMemo(
    () => (view.power_ups ?? []).filter((row) => row.role === view.you.role),
    [view.power_ups, view.you.role],
  )
  const tauntCooldown = view.you.taunt_cooldown_s ?? 0
  const tauntEnabled = view.you.taunt_enabled !== false
  const youActive = view.you.status === 'active'
  const canTaunt =
    isHider && view.phase === 'active' && tauntEnabled && youActive
  // Server hint is a dict. Never render it as a React child — that unmounts the app.
  const hintText = hintLine(view.you.role, view.you.hint)
  // Prefer shield (and other public timed effects) so the countdown is always visible.
  const effectLines = (view.active_effects ?? [])
    .filter((row) => row.remaining_s > 0)
    .map((row) => effectHudLine(row, view.you.player_id))

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
    if (!map || playBoundary?.kind !== 'circle' || !zoneTimer?.next_radius_m) {
      shrinkPreviewRef.current?.remove()
      shrinkPreviewRef.current = null
      return
    }
    const center = playBoundary.circle.center
    const latLng: L.LatLngExpression = [center.lat, center.lon]
    const style = {
      color: '#f0c75e',
      weight: 1,
      dashArray: '6 8',
      fill: false,
      opacity: 0.75,
    }
    if (!shrinkPreviewRef.current) {
      shrinkPreviewRef.current = L.circle(latLng, {
        radius: zoneTimer.next_radius_m,
        ...style,
      }).addTo(map)
    } else {
      shrinkPreviewRef.current.setLatLng(latLng)
      shrinkPreviewRef.current.setRadius(zoneTimer.next_radius_m)
      shrinkPreviewRef.current.setStyle(style)
    }
  }, [playBoundary, zoneTimer?.next_radius_m, zoneTimer?.radius_m])

  useEffect(() => {
    const added = newRevealIds(prevRevealsRef.current, view.reveals)
    prevRevealsRef.current = view.reveals
    if (added.length === 0) {
      // A later view often refreshes expires_in_s on the same reveal. Clearing
      // the timer here left "PINGED" on screen for the rest of the ping.
      return
    }
    const selfPing = (view.reveals ?? []).some(
      (r) => added.includes(r.reveal_id) && r.player_id === view.you.player_id,
    )
    // Priority 3. Queued behind tag, out-of-bounds, and went-dark alerts, never dropped.
    enqueueAlert({
      key: selfPing ? 'ping:self' : 'ping:other',
      text: selfPing ? 'PING' : 'PINGED',
      tone: 'warn',
      priority: 3,
    })
  }, [view.reveals, view.you.player_id, enqueueAlert])

  // Safety and danger banners from the server (a player went dark, ...). Each banner id
  // alerts once. A player going dark shares one key with their own `dark:` alert below and
  // with repeats, so a flapping signal collapses into a single queue entry. Other banners
  // ("Stay in spawn") describe an ongoing state and stay in the HUD instead.
  useEffect(() => {
    const seen = seenBannerIdsRef.current
    const current = new Set<string>()
    for (const banner of view.banners ?? []) {
      current.add(banner.banner_id)
      if (seen.has(banner.banner_id) || !isAlertBanner(banner)) {
        continue
      }
      enqueueAlert({
        key:
          banner.tone === 'safety' && banner.player_id
            ? `dark:${banner.player_id}`
            : `banner:${banner.player_id ?? 'game'}:${banner.title}`,
        text: banner.detail ? `${banner.title} — ${banner.detail}` : banner.title,
        tone: banner.tone === 'safety' ? 'safety' : 'danger',
        priority: banner.tone === 'safety' ? 2 : 1,
      })
    }
    seenBannerIdsRef.current = current
  }, [view.banners, enqueueAlert])

  // Your own state changes. The persistent text stays in the HUD; the alert is the nudge.
  const youStatus = view.you.status
  const youId = view.you.player_id
  useEffect(() => {
    if (youStatus === 'eliminated') {
      enqueueAlert({
        key: 'out:self',
        text: "You're out — A seeker tagged you. Stay safe and wait for the hunt to end.",
        tone: 'danger',
        priority: 1,
      })
    } else if (youStatus === 'signal_lost') {
      enqueueAlert({
        // Same key the server banner for this player uses, so one event is one alert.
        key: `dark:${youId}`,
        text: 'Signal lost. Check that your screen is on.',
        tone: 'safety',
        priority: 2,
      })
    }
  }, [youStatus, youId, enqueueAlert])

  const boundsPhase = view.you.bounds?.phase ?? 'inside'
  useEffect(() => {
    if (boundsPhase === 'inside') {
      return
    }
    enqueueAlert({
      // One key for every outside phase, so warning -> countdown refreshes one entry.
      key: 'oob:self',
      text: boundsPhase === 'penalized' ? 'Tagged out of bounds.' : 'Out of bounds. Walk back in.',
      tone: 'danger',
      priority: 1,
    })
  }, [boundsPhase, enqueueAlert])

  // One-off messages from actions (power denied, tag accepted, ...). Lowest priority.
  // Depends on the state object, so setting the same text again alerts again.
  useEffect(() => {
    if (!localNoteState) {
      return
    }
    enqueueAlert({
      key: `note:${localNoteState.text}`,
      text: localNoteState.text,
      tone: 'info',
      priority: 4,
    })
  }, [localNoteState, enqueueAlert])

  useEffect(() => {
    const map = mapRef.current
    if (!map || !powerPick || (powerPick.step !== 'map' && powerPick.step !== 'zone_point')) {
      return
    }
    function onMapClick(event: L.LeafletMouseEvent) {
      const point = { lat: event.latlng.lat, lon: event.latlng.lng }
      if (!pointInPlayArea(point, playBoundary)) {
        setLocalNote('That point is outside the play area.')
        return
      }
      const pick = powerPick
      if (!pick) {
        return
      }
      if (pick.step === 'map') {
        void submitPower(pick.powerId, { lat: point.lat, lon: point.lon })
      } else if (pick.step === 'zone_point') {
        void submitPower(pick.powerId, {
          zone_id: pick.zoneId,
          lat: point.lat,
          lon: point.lon,
        })
      }
      setPowerPick(null)
    }
    map.on('click', onMapClick)
    return () => {
      map.off('click', onMapClick)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [powerPick, playBoundary])

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
        circle.bindPopup(textPopup(`${pin.display_name} · ping`))
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
    const now = performance.now()
    for (const pin of pins) {
      seen.add(pin.playerId)
      let marker = markersRef.current.get(pin.playerId)
      const label = `${pin.displayName} (${pin.role})${pin.isYou ? ' · you' : ''}${
        pin.status === 'signal_lost' ? ' · dark' : ''
      }`
      if (!marker) {
        marker = L.marker([pin.lat, pin.lon]).addTo(map)
        marker.bindPopup(textPopup(label))
        markersRef.current.set(pin.playerId, marker)
        pinAnimRef.current.set(pin.playerId, {
          from: { lat: pin.lat, lon: pin.lon },
          started: now,
        })
      } else {
        const anim = pinAnimRef.current.get(pin.playerId)
        const current = marker.getLatLng()
        pinAnimRef.current.set(pin.playerId, {
          from: { lat: current.lat, lon: current.lng },
          started: now,
        })
        if (
          !anim ||
          Math.abs(anim.from.lat - pin.lat) > 1e-7 ||
          Math.abs(anim.from.lon - pin.lon) > 1e-7
        ) {
          const glide = glidePoint(
            pinAnimRef.current.get(pin.playerId)!.from,
            { lat: pin.lat, lon: pin.lon },
            0,
          )
          marker.setLatLng([glide.lat, glide.lon])
        }
        marker.setPopupContent(textPopup(label))
      }
    }
    for (const [id, marker] of markersRef.current) {
      if (!seen.has(id)) {
        marker.remove()
        markersRef.current.delete(id)
        pinAnimRef.current.delete(id)
      }
    }
    const tick = () => {
      const tNow = performance.now()
      let animating = false
      for (const pin of pins) {
        const anim = pinAnimRef.current.get(pin.playerId)
        const marker = markersRef.current.get(pin.playerId)
        if (!anim || !marker) {
          continue
        }
        const elapsed = tNow - anim.started
        const point = glidePoint(anim.from, { lat: pin.lat, lon: pin.lon }, elapsed)
        marker.setLatLng([point.lat, point.lon])
        if (elapsed < PIN_GLIDE_MS) {
          animating = true
        }
      }
      if (animating) {
        pinRafRef.current = window.requestAnimationFrame(tick)
      } else {
        pinRafRef.current = null
      }
    }
    if (pinRafRef.current == null) {
      pinRafRef.current = window.requestAnimationFrame(tick)
    }
    return () => {
      if (pinRafRef.current != null) {
        window.cancelAnimationFrame(pinRafRef.current)
        pinRafRef.current = null
      }
    }
  }, [pins])

  useEffect(() => {
    // The safety overlay mounts this map so Leaflet survives Continue.
    // Do not publish the arena-center seed until the player has acknowledged it.
    if (holdPresence) {
      return
    }
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
          // One reset replaces a desk seed the server would otherwise pin in place.
          flag: fix.reset ? 'reset' : 'normal',
        })
      },
      onError: (message) => setLocalNote(message),
    })
    return () => stop()
  }, [socket, watchLocation, arenaKey, holdPresence])

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

  async function runDock(action: () => Promise<PlayerView>) {
    setBusyDock(true)
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
      setBusyDock(false)
    }
  }

  async function submitPower(
    powerId: string,
    extra: {
      lat?: number
      lon?: number
      target_player_id?: string
      zone_id?: string
    },
  ) {
    await runDock(() =>
      withAuthRetry((token) =>
        purchasePowerUp({ token, gameId: view.game_id, id: powerId, ...extra }),
      ),
    )
  }

  function onPowerChip(row: (typeof powerUps)[number]) {
    const request = powerUpRequest(view, row)
    const decision = decide(request)
    if (decision.kind === 'denied' && !chipIsTappable(request) && !chipShowsDenialOnTap(request)) {
      setLocalNote(denialMessage(decision.reason))
      return
    }
    if (requiresZoneTarget(row.id)) {
      setPowerPick({ step: 'zone', powerId: row.id })
      return
    }
    if (requiresMapPoint(row.id)) {
      setPowerPick({ step: 'map', powerId: row.id })
      setLocalNote('Tap the map to place that power.')
      return
    }
    if (requiresPlayerTarget(row.id)) {
      setPowerPick({ step: 'rescue', powerId: row.id })
      return
    }
    void submitPower(row.id, {})
  }

  function onPickZone(zoneId: string) {
    if (!powerPick || powerPick.step !== 'zone') {
      return
    }
    setPowerPick({ step: 'zone_point', powerId: powerPick.powerId, zoneId })
    setLocalNote('Tap where to move that safe zone.')
  }

  function onRescueTarget(targetId: string) {
    if (!powerPick || powerPick.step !== 'rescue') {
      return
    }
    setPowerPick(null)
    void submitPower(powerPick.powerId, { target_player_id: targetId })
  }

  function onBlock(playerId: string, displayName: string) {
    setPendingBlock({ id: playerId, name: displayName })
  }

  function onReport(playerId: string, displayName: string) {
    window.location.href = reportMailto({
      gameId: view.game_id,
      playerId,
      displayName,
      supportEmail: SUPPORT_EMAIL,
    })
  }

  // Filter socket "too fast" noise out of the HUD.
  const socketNote =
    note && note.toLowerCase().includes('too fast') ? null : note
  // Persistent state (not an alert): stays until the condition clears.
  const statusLine = wentDark ?? oobNote ?? socketNote
  const statusIsWarn = Boolean(wentDark || oobNote)
  // Ongoing-state banners (spawn lock, safe time up) stay visible; only news is an alert.
  const stateBanners = (view.banners ?? []).filter((banner) => !isAlertBanner(banner))

  return (
    <main className={`live-map live-map--stacked${overlayOpen ? ' live-map--overlay' : ''}`}>
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
          <button type="button" className="chip" onClick={() => setPanel('log')}>
            Log
          </button>
          <button type="button" className="chip chip--accent" onClick={() => setPendingLeave(true)}>
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
          {seekerPingLeft != null ? (
            <span className="hud-sub">Seekers {formatClock(seekerPingLeft)}</span>
          ) : null}
          {zoneTimer?.shrinks_in_s != null && playBoundary?.kind === 'circle' ? (
            <span className="hud-sub">Shrink {formatClock(zoneTimer.shrinks_in_s)}</span>
          ) : null}
          <span className="hud-sub">{view.you.points ?? 0} pts</span>
          {accuracyM != null ? (
            <span className={`hud-sub${accuracyM > 30 ? ' hud-sub--warn' : ''}`}>
              GPS ±{Math.round(accuracyM)} m
            </span>
          ) : (
            <span className="hud-sub hud-sub--warn">GPS…</span>
          )}
          {/* aria-live off: the matching one-shot alert is what a screen reader announces. */}
          {statusLine ? (
            <span
              className={`hud-hint${statusIsWarn ? ' hud-hint--warn' : ''}`}
              aria-live="off"
            >
              {statusLine}
            </span>
          ) : null}
          {stateBanners.map((banner) => (
            <span key={banner.banner_id} className="hud-hint hud-hint--warn" aria-live="off">
              {banner.detail ? `${banner.title} — ${banner.detail}` : banner.title}
            </span>
          ))}
          {hintText ? <span className="hud-hint">{hintText}</span> : null}
          {effectLines.map((line) => (
            <span key={line} className="hud-sub hud-sub--effect">
              {line}
            </span>
          ))}
        </div>
      ) : null}

      {/* Zero-height anchor: the alert overlays the map and never changes its height. */}
      {/*
        The live region is always mounted and only its text changes: many screen readers
        skip a region that is created together with its content. Tag, out-of-bounds and
        safety alerts are assertive; ping and updates are polite. The key makes a resumed
        alert a new node, so it is announced again.
      */}
      <div className="alert-anchor">
        <div
          className={`banners${shownAlert && !overlayOpen ? '' : ' banners--empty'}`}
          aria-live={shownAlert && shownAlert.priority <= 2 ? 'assertive' : 'polite'}
          aria-atomic="true"
        >
          {shownAlert && !overlayOpen ? (
            <p key={shownAlert.showId} className={`banner banner--${shownAlert.tone}`}>
              {shownAlert.text}
            </p>
          ) : null}
        </div>
      </div>

      <div
        className={`map-frame${overlayOpen ? ' map-frame--hidden' : ''}`}
        ref={mapEl}
        role="presentation"
        aria-hidden={overlayOpen}
      />

      {!overlayOpen ? (
        <footer className="bottom-stack">
          {toast ? (
            <p className="toast" role="status">
              {toast}
            </p>
          ) : null}
          <div className="dock">
            {isHider && youActive ? (
              <button type="button" className="chip chip--accent" disabled={!qrToken} onClick={() => setPanel('show')}>
                Show tag
              </button>
            ) : null}
            {isSeeker && view.phase === 'active' && youActive ? (
              <button type="button" className="chip chip--accent" onClick={() => setPanel('scan')}>
                Scan tag
              </button>
            ) : null}
            {isSeeker && view.phase === 'head_start' ? (
              <p className="dock-note">Seekers cannot tag until head start ends.</p>
            ) : null}
            {isHider && youActive && !qrToken ? (
              <p className="dock-note">Waiting for a tag QR from the server…</p>
            ) : null}
            {canTaunt ? (
              <button
                type="button"
                className="chip"
                disabled={busyDock || tauntCooldown > 0}
                onClick={() =>
                  void runDock(() =>
                    withAuthRetry((token) => tauntGame({ token, gameId: view.game_id })),
                  )
                }
              >
                {tauntCooldown > 0 ? `Taunt ${formatClock(tauntCooldown)}` : 'Taunt'}
              </button>
            ) : null}
            {powerUps.length > 0 ? (
              <div className="chip-row power-dock" aria-label="Power-ups">
                {powerUps.map((row) => {
                  const request = powerUpRequest(view, row)
                  const tappable = chipIsTappable(request)
                  const denialTap = chipShowsDenialOnTap(request)
                  const disabled = busyDock || (!tappable && !denialTap)
                  return (
                    <button
                      key={row.id}
                      type="button"
                      className={`chip${tappable ? '' : ' chip--muted'}`}
                      disabled={disabled}
                      onClick={() => onPowerChip(row)}
                    >
                      {row.title} · {row.cost}
                    </button>
                  )
                })}
              </div>
            ) : null}
          </div>
          {powerPick?.step === 'zone' ? (
            <div className="pick-banner">
              <p>Pick a safe zone to move</p>
              <div className="chip-row">
                {(view.arena?.zones ?? [])
                  .filter((z) => z.kind === 'safe')
                  .map((zone) => (
                    <button
                      key={zone.id}
                      type="button"
                      className="chip"
                      onClick={() => onPickZone(zone.id)}
                    >
                      {zone.name}
                    </button>
                  ))}
                <button type="button" className="chip" onClick={() => setPowerPick(null)}>
                  Cancel
                </button>
              </div>
            </div>
          ) : null}
          {powerPick?.step === 'rescue' ? (
            <div className="pick-banner">
              <p>Pick a player to rescue</p>
              <div className="chip-row">
                {rescueCandidates(view).map((player) => (
                  <button
                    key={player.player_id}
                    type="button"
                    className="chip"
                    onClick={() => onRescueTarget(player.player_id)}
                  >
                    {player.display_name}
                  </button>
                ))}
                <button type="button" className="chip" onClick={() => setPowerPick(null)}>
                  Cancel
                </button>
              </div>
            </div>
          ) : null}
          {powerPick?.step === 'map' || powerPick?.step === 'zone_point' ? (
            <div className="pick-banner">
              <p>Tap the map to place your power</p>
              <button type="button" className="chip" onClick={() => setPowerPick(null)}>
                Cancel
              </button>
            </div>
          ) : null}
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

      {pendingLeave ? (
        <ConfirmDialog
          title="Leave this hunt?"
          confirmLabel="Leave"
          onConfirm={() => {
            setPendingLeave(false)
            onLeave()
          }}
          onCancel={() => setPendingLeave(false)}
        />
      ) : null}
      {pendingBlock ? (
        <ConfirmDialog
          title="Block this player?"
          message="Their pin stays on the map as “Blocked Player #…”. You can unblock them in Account."
          confirmLabel="Block"
          onConfirm={() => {
            const pending = pendingBlock
            setPendingBlock(null)
            blockPlayer(pending.id, pending.name)
            setBlockRevision((n) => n + 1)
            setToast(`${displayNameFor(pending.id, pending.name)} blocked on this device.`)
          }}
          onCancel={() => setPendingBlock(null)}
        />
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
            onTagged={(next) => {
              onView(next)
              setLocalNote('Tag accepted.')
              setToast('Tag accepted.')
              setPanel('map')
            }}
            onSignedOut={onSignedOut}
          />
        </div>
      ) : null}
      {panel === 'log' ? (
        <div className="qr-overlay">
          <EventLog
            gameId={view.game_id}
            onClose={() => setPanel('map')}
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
          <Leaderboard view={view} onBlock={onBlock} onReport={onReport} />
        </div>
      ) : null}
    </main>
  )
}
