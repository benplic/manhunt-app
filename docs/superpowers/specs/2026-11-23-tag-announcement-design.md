# Tag Announcement Design

## Goal

Every connected player sees a short full-screen announcement when a hider is
tagged. This includes seeker tags and out-of-bounds auto-tags.

## Event contract

Tag announcements use the existing non-sensitive WebSocket `event` envelope.
The server adds two structured fields:

- `announcement`: `"player_tagged"` or `"player_tagged_out_of_bounds"`
- `subject_name`: the tagged player's display name

The existing `type`, `text`, `tone`, `player_id`, and timeline payload remain
unchanged. The structured fields prevent clients from parsing display names out
of prose. A normal tag uses `type: "tag"` and
`announcement: "player_tagged"`. An out-of-bounds auto-tag uses
`type: "out_of_bounds"` and
`announcement: "player_tagged_out_of_bounds"`.

Tag conversion uses the normal `player_tagged` announcement because the
tag action succeeded even though the player remains active as a seeker.

## Presentation

Both clients render an ephemeral, non-blocking overlay at the live/results
root boundary:

- Normal tag: `Riley was tagged!`
- Out of bounds: `Riley was tagged out of bounds!`
- Duration: 2 seconds
- Visual: large centered text plus a red full-screen edge flash
- Interaction: overlay never captures taps
- Accessibility: announce the sentence as a status update; Reduce Motion keeps
  the text and static flash but removes scaling or travel animation
- iOS: warning haptic

The existing iOS event pill and event log remain. The web client starts
consuming `onEvent`; unrelated events do not create this overlay.

## Queue and reconnect behavior

Announcements form a FIFO queue. If two tags arrive close together, each gets
its own 2-second presentation rather than replacing the first.

The socket sequence remains the deduplication boundary. Both clients remember
the highest sequence they have consumed through the existing socket state.
Replayed events with a sequence at or below that value do not produce a second
announcement. A genuinely missed event replayed after reconnect is shown once.

## Boundaries

- No persistent snapshot banner is added to `GameState`; these announcements
  are transient events.
- No coordinates or sensitive fields are added to the event.
- The server remains the source of truth. Clients do not infer tags from status
  changes.
- Events are accepted only while the live game screen is active. An
  announcement that started live may remain visible and finish its two-second
  timer over results, including the final game-ending tag. Lobby never shows
  an announcement.
- Clients pass `subject_name` through their device-local block list using the
  structured `player_id`; they do not parse prose or infer the subject.

## Tests

- Server engine tests assert both tag paths emit the structured announcement
  and subject name.
- WebSocket simulation asserts every connected player receives the structured
  fields.
- iOS unit tests cover event decoding, queue order, expiry, and exact copy.
- Web unit tests cover event wiring, queue order, expiry, exact copy, and
  unrelated-event filtering.
