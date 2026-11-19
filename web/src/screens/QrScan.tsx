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
  const claimedRef = useRef(false)
  const scannerRef = useRef<Html5Qrcode | null>(null)

  async function claim(token: string) {
    if (claimedRef.current || busy) {
      return
    }
    claimedRef.current = true
    setBusy(true)
    setError(null)
    try {
      await withAuthRetry((access) =>
        claimQrTag({ token: access, gameId, qrToken: token }),
      )
      onTagged()
    } catch (err) {
      claimedRef.current = false
      if (err instanceof SessionExpiredError) {
        onSignedOut()
        return
      }
      setError(err instanceof ApiError ? err.message : (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => {
    if (injectScan) {
      void claim(injectScan)
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
      const active = scannerRef.current
      scannerRef.current = null
      if (active) {
        void active
          .stop()
          .then(() => active.clear())
          .catch(() => {
            // TODO: surface scanner cleanup failures if they become common on iOS.
          })
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gameId, injectScan])

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
      <button type="button" onClick={onClose}>
        Close
      </button>
    </main>
  )
}
