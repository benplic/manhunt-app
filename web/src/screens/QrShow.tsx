import { useEffect, useState } from 'react'
import QRCode from 'qrcode'
import './QrShow.css'

type Props = {
  token: string
  onClose: () => void
}

export function QrShow({ token, onClose }: Props) {
  const [dataUrl, setDataUrl] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    QRCode.toDataURL(token, { width: 280, margin: 1 })
      .then((url) => {
        if (!cancelled) {
          setDataUrl(url)
        }
      })
      .catch(() => {
        if (!cancelled) {
          setError('Could not draw the tag code.')
        }
      })
    return () => {
      cancelled = true
    }
  }, [token])

  return (
    <main className="qr-show">
      <h1>Your tag code</h1>
      <p>Show this to a seeker. It rotates about every 30 seconds and scans from either app.</p>
      {dataUrl ? <img src={dataUrl} alt="Tag QR code" width={280} height={280} /> : null}
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
