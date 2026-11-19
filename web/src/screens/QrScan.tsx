import { useEffect, useRef, useState } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { ApiError } from '../api/client'
import { claimQrTag } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import './QrScan.css'

type Props = {
  gameId: string
  onClose: () => void
  onTagged: () => void
  onSignedOut: () => void
  /** Test-only: claim this token instead of opening the camera. */
  injectScan?: string | null
}

/**
 * Camera QR scan. iOS Safari has no BarcodeDetector; html5-qrcode works there.
 * Pairing distance stays server-side (about 30 m).
 */
export function QrScan({
  gameId,
  onClose,
  onTagged,
  onSignedOut,
  injectScan = null,
}: Props) {
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [paused, setPaused] = useState(false)
  const claimedRef = useRef(false)
  const scannerRef = useRef<Html5Qrcode | null>(null)

  async function stopScanner() {
    const active = scannerRef.current
    if (!active) {
      return
    }
    try {
      await active.stop()
      active.clear()
    } catch {
      // TODO: surface scanner cleanup failures if they become common on iOS.
    }
    scannerRef.current = null
  }

  async function claim(token: string) {
    if (claimedRef.current || busy) {
      return
    }
    claimedRef.current = true
    setBusy(true)
    setError(null)
    // Stop the camera immediately so failed claims do not spam /tags/qr at 8 fps.
    await stopScanner()
    setPaused(true)
    try {
      await withAuthRetry((access) =>
        claimQrTag({ token: access, gameId, qrToken: token }),
      )
      onTagged()
    } catch (err) {
      if (err instanceof SessionExpiredError) {
        onSignedOut()
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  function retryScan() {
    claimedRef.current = false
    setError(null)
    setPaused(false)
  }

  useEffect(() => {
    if (injectScan) {
      void claim(injectScan)
      return
    }
    if (paused) {
      return
    }

    const scanner = new Html5Qrcode('manhunt-qr-reader')
    scannerRef.current = scanner
    let stopped = false

    scanner
      .start(
        { facingMode: 'environment' },
        { fps: 8, qrbox: { width: 240, height: 240 } },
        (decoded) => {
          void claim(decoded)
        },
        () => {
          // Ignore per-frame "not found" noise.
        },
      )
      .catch(() => {
        if (!stopped) {
          setError('Camera permission is required to scan a tag code.')
        }
      })

    return () => {
      stopped = true
      void stopScanner()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gameId, injectScan, paused])

  return (
    <main className="qr-scan">
      <h1>Scan tag</h1>
      <p>Point at a hider’s code. The server rejects tags that are too far.</p>
      <div id="manhunt-qr-reader" className="reader" />
      {busy ? <p>Claiming…</p> : null}
      {error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : null}
      <div className="actions">
        {paused && error ? (
          <button type="button" onClick={retryScan}>
            Try again
          </button>
        ) : null}
        <button type="button" onClick={onClose}>
          Close
        </button>
      </div>
    </main>
  )
}
