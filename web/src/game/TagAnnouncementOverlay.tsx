import type { TagAnnouncement } from './tagAnnouncements'
import './TagAnnouncementOverlay.css'

type Props = {
  announcement: TagAnnouncement | null
}

export function TagAnnouncementOverlay({ announcement }: Props) {
  if (!announcement) {
    return null
  }
  return (
    <div
      className="tag-announcement"
      role="status"
      aria-live="assertive"
      aria-atomic="true"
    >
      <p>{announcement.text}</p>
    </div>
  )
}
