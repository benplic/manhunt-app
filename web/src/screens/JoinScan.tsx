import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { parseJoinPayload, sanitizeJoinCode } from '../api/joinCode'
import { releaseScanner } from './scannerRelease'
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
  const [manual, setManual] = useState('')
  const [manualOpen, setManualOpen] = useState(false)
  const doneRef = useRef(false)
  const scannerRef = useRef<Html5Qrcode | null>(null)
  const startPromiseRef = useRef<Promise<unknown>>(Promise.resolve())

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
    void releaseScanner(startPromiseRef.current, () => stopScanner()).then(() => onCode(code))
  }

  function onManualSubmit(event: FormEvent) {
    event.preventDefault()
    const code = sanitizeJoinCode(manual)
    if (code.length !== 6) {
      setError('Join codes are 6 characters.')
      return
    }
    accept(code)
  }

  useEffect(() => {
    if (injectScan) {
      accept(injectScan)
      return
    }

    const scanner = new Html5Qrcode('manhunt-join-reader')
    scannerRef.current = scanner
    let stopped = false

    const pending = scanner.start(
      { facingMode: 'environment' },
      { fps: 8, qrbox: { width: 240, height: 240 } },
      (decoded) => {
        accept(decoded)
      },
      () => undefined,
    )
    startPromiseRef.current = pending
    pending.catch(() => {
      if (!stopped) {
        setManualOpen(true)
        setError('Camera blocked—enter the join code.')
      }
    })

    return () => {
      stopped = true
      void releaseScanner(pending, () => stopScanner(scanner))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [injectScan])

  return (
    <main className="qr-scan qr-scan--dark">
      <h1>Scan join code</h1>
      <p>Point at the host’s lobby QR.</p>
      <div id="manhunt-join-reader" className="reader" />
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
              Join code
              <input
                value={manual}
                onChange={(e) => setManual(sanitizeJoinCode(e.target.value))}
                autoCapitalize="characters"
                maxLength={6}
                placeholder="6-character join code"
              />
            </label>
            <button type="submit">Join with code</button>
          </>
        )}
      </form>
      <button type="button" className="secondary" onClick={onClose}>
        Close
      </button>
    </main>
  )
}
