import { useEffect, useState } from 'react'
import type { TagAnnouncement } from './tagAnnouncements'
import './TagAnnouncementOverlay.css'

/** Matches the `transition` on `.tag-announcement--leaving` in the stylesheet. */
const FADE_OUT_MS = 450

type Props = {
  announcement: TagAnnouncement | null
}

export function TagAnnouncementOverlay({ announcement }: Props) {
  // The last flash stays mounted while it fades out, so the screen does not snap clear.
  const [shown, setShown] = useState<TagAnnouncement | null>(announcement)
  if (announcement && announcement !== shown) {
    setShown(announcement)
  }
  const leaving = announcement === null && shown !== null

  useEffect(() => {
    if (announcement || !shown) {
      return undefined
    }
    const timer = window.setTimeout(() => setShown(null), FADE_OUT_MS)
    return () => window.clearTimeout(timer)
  }, [announcement, shown])

  if (!shown) {
    return null
  }
  return (
    <div
      className={`tag-announcement${leaving ? ' tag-announcement--leaving' : ''}`}
      role="status"
      aria-live="assertive"
      aria-atomic="true"
    >
      <p key={shown.seq}>{shown.text}</p>
    </div>
  )
}
