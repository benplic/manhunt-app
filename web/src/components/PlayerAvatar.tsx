import { AVATAR_TEXT, initialsFor, type AvatarStyle } from '../game/avatarStyle'
import './Roster.css'

type Props = {
  name: string
  style: AvatarStyle | undefined
  size?: number
}

/**
 * Initials avatar. The ring pattern (none, solid, dashed, dotted) is a second cue next to
 * the fill color, so same-initial players stay distinct for color-blind players.
 * TODO: profile photos. Needs upload, storage, moderation, and PII decisions first.
 */
export function PlayerAvatar({ name, style, size = 32 }: Props) {
  return (
    <span
      aria-hidden="true"
      className={`player-avatar player-avatar--cue-${style?.cue ?? 0}`}
      style={{
        width: size,
        height: size,
        fontSize: Math.round(size * 0.38),
        background: style?.color ?? '#9aa0ad',
        color: AVATAR_TEXT,
      }}
    >
      {initialsFor(name)}
    </span>
  )
}
