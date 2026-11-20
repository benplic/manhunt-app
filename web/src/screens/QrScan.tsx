import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { ApiError } from '../api/client'
import { claimQrTag } from '../api/games'
import { SessionExpiredError, withAuthRetry } from '../api/session'
import { isAccuracyTooFuzzy, localAccuracyBlockMessage } from '../api/tagErrors'
import { releaseScanner } from './scannerRelease'
import './QrScan.css'

type Props = {
  gameId: string
  onClose: () => void
  onTagged: () => void
  onSignedOut: () => void
  /** Latest GPS accuracy from this phone. Null until the first fix. */
  accuracyM?: number | null
  /** Test-only: claim this token instead of opening the camera. */
  injectScan?: string | null
}

const HOLD_MS = 8000

/**
 * Camera QR scan. iOS Safari has no BarcodeDetector; html5-qrcode works there.
 * Pairing distance stays server-side (about 30 m). Coarse GPS is blocked locally
 * so we do not spam /tags/qr; one decoded token may wait briefly for a clearer fix.
 */
export function QrScan({
  gameId,
  onClose,
  onTagged,
  onSignedOut,
  accuracyM = null,
  injectScan = null,
}: Props) {
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [paused, setPaused] = useState(false)
  const [manual, setManual] = useState('')
  const [manualOpen, setManualOpen] = useState(false)
  const [heldNote, setHeldNote] = useState<string | null>(null)
  const claimedRef = useRef(false)
  const scannerRef = useRef<Html5Qrcode | null>(null)
  const heldTokenRef = useRef<string | null>(null)
  const heldUntilRef = useRef(0)
  const accuracyRef = useRef(accuracyM)
  /** start() must settle before stop(), or the camera stream is left running. */
  const startPromiseRef = useRef<Promise<unknown>>(Promise.resolve())

  useEffect(() => {
    accuracyRef.current = accuracyM
    // If we were holding a token for clearer GPS, try once accuracy improves.
    if (
      heldTokenRef.current &&
      Date.now() <= heldUntilRef.current &&
      !isAccuracyTooFuzzy(accuracyM)
    ) {
      const token = heldTokenRef.current
      heldTokenRef.current = null
      setHeldNote(null)
      void claim(token)
    }
  }, [accuracyM])

  async function stopScanner(target?: Html5Qrcode | null) {
    const active = target ?? scannerRef.current
    if (!active) {
      return
    }
    if (scannerRef.current === active) {
      scannerRef.current = null
    }
    try {
      await active.stop()
      active.clear()
    } catch {
      // TODO: surface scanner cleanup failures if they become common on iOS.
    }
  }

  async function claim(token: string) {
    if (claimedRef.current || busy) {
      return
    }
    const accuracy = accuracyRef.current
    if (isAccuracyTooFuzzy(accuracy)) {
      // Hold one decoded token briefly; do not POST while GPS is unusable.
      heldTokenRef.current = token
      heldUntilRef.current = Date.now() + HOLD_MS
      setHeldNote(
        accuracy == null
          ? 'Waiting for GPS… keep the code in view.'
          : localAccuracyBlockMessage(accuracy),
      )
      window.setTimeout(() => {
        if (heldTokenRef.current === token && Date.now() >= heldUntilRef.current) {
          heldTokenRef.current = null
          setHeldNote('GPS stayed fuzzy. Get a clearer fix, then scan again.')
        }
      }, HOLD_MS + 50)
      return
    }

    claimedRef.current = true
    setBusy(true)
    setError(null)
    setHeldNote(null)
    // Stop only after start() has reached the scanning state. An early stop()
    // throws and leaves getUserMedia running, so the next open looks camera-blocked.
    await releaseScanner(startPromiseRef.current, () => stopScanner())
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
    heldTokenRef.current = null
    setError(null)
    setHeldNote(null)
    setPaused(false)
  }

  function onManualSubmit(event: FormEvent) {
    event.preventDefault()
    const token = manual.trim()
    if (!token) {
      setError('Enter the hider’s tag code.')
      return
    }
    void claim(token)
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

    const pending = scanner.start(
      { facingMode: 'environment' },
      { fps: 8, qrbox: { width: 240, height: 240 } },
      (decoded) => {
        void claim(decoded)
      },
      () => {
        // Ignore per-frame "not found" noise.
      },
    )
    startPromiseRef.current = pending
    pending.catch(() => {
      if (!stopped) {
        setManualOpen(true)
        setError('Camera blocked—paste the hider’s code.')
      }
    })

    return () => {
      stopped = true
      // Stop this instance after start settles, not whatever scannerRef points at later.
      void releaseScanner(pending, () => stopScanner(scanner))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gameId, injectScan, paused])

  return (
    <main className="qr-scan qr-scan--dark">
      <h1>Scan tag</h1>
      <p>Point at a hider’s code. Both phones need clear GPS within about 30 m.</p>
      {accuracyM != null ? (
        <p className={`accuracy${isAccuracyTooFuzzy(accuracyM) ? ' accuracy--warn' : ''}`}>
          Your GPS ±{Math.round(accuracyM)} m
        </p>
      ) : (
        <p className="accuracy accuracy--warn">Waiting for GPS…</p>
      )}
      <div id="manhunt-qr-reader" className="reader" />
      {busy ? <p>Claiming…</p> : null}
      {heldNote ? (
        <p className="held" role="status">
          {heldNote}
        </p>
      ) : null}
      {error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : null}
      <form className={`manual${manualOpen ? ' manual--open' : ''}`} onSubmit={onManualSubmit}>
        {!manualOpen ? (
          <button type="button" className="secondary" onClick={() => setManualOpen(true)}>
            Enter code manually
          </button>
        ) : (
          <>
            <label>
              Tag code
              <input
                value={manual}
                onChange={(e) => setManual(e.target.value)}
                autoCapitalize="off"
                autoCorrect="off"
                spellCheck={false}
                placeholder="Paste or type the rotating code"
              />
            </label>
            <button type="submit" disabled={busy}>
              Submit code
            </button>
          </>
        )}
      </form>
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
