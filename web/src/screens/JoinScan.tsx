import { useEffect, useRef, useState } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { parseJoinPayload } from '../api/joinCode'
import './QrScan.css'

type Props = {
  onCode: (code: string) => void
  onClose: () => void
  /** Test-only: claim this payload instead of opening the camera. */
  injectScan?: string | null
}

/** Camera scan for lobby join links / bare join codes. */
export function JoinScan({ onCode, onClose, injectScan = null }: Props) {
  const [error, setError] = useState<string | null>(null)
  const doneRef = useRef(false)
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

  function accept(raw: string) {
    if (doneRef.current) {
      return
    }
    const code = parseJoinPayload(raw)
    if (code.length !== 6) {
      setError('That QR is not a Manhunt join code.')
      return
    }
    doneRef.current = true
    void stopScanner().then(() => onCode(code))
  }

  useEffect(() => {
    if (injectScan) {
      accept(injectScan)
      return
    }

    const scanner = new Html5Qrcode('manhunt-join-reader')
    scannerRef.current = scanner
    let stopped = false

    scanner
      .start(
        { facingMode: 'environment' },
        { fps: 8, qrbox: { width: 240, height: 240 } },
        (decoded) => {
          accept(decoded)
        },
        () => undefined,
      )
      .catch(() => {
        if (!stopped) {
          setError('Camera permission is required to scan a join code.')
        }
      })

    return () => {
      stopped = true
      void stopScanner()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [injectScan])

  return (
    <main className="qr-scan">
      <h1>Scan join code</h1>
      <p>Point at the host’s lobby QR.</p>
      <div id="manhunt-join-reader" className="reader" />
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
