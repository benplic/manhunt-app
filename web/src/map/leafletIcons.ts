import L from 'leaflet'
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

let configured = false

/** Vite-safe default marker URLs (avoids broken relative paths in production). */
export function ensureLeafletDefaultIcons(): void {
  if (configured) {
    return
  }
  L.Icon.Default.mergeOptions({
    iconRetinaUrl: markerIcon2x,
    iconUrl: markerIcon,
    shadowUrl: markerShadow,
  })
  configured = true
}

export function leafletIconUrlsForTests(): { iconUrl: string; shadowUrl: string } {
  ensureLeafletDefaultIcons()
  const proto = L.Icon.Default.prototype as unknown as {
    options: { iconUrl: string; shadowUrl: string }
  }
  return {
    iconUrl: proto.options.iconUrl,
    shadowUrl: proto.options.shadowUrl,
  }
}
