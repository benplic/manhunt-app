# Tag Announcements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every live player a queued two-second full-screen announcement when a hider is tagged normally or auto-tagged out of bounds.

**Architecture:** The engine adds structured announcement fields to the existing non-sensitive game event payload. Realtime delivery copies those fields into both live and replayed WebSocket envelopes. iOS and web decode the event into a small FIFO presentation queue and render a non-blocking overlay above the live map.

**Tech Stack:** FastAPI/Python engine with pytest, SwiftUI/XCTest on iOS 18.4, React/TypeScript with Vitest.

## Global Constraints

- Copy is exactly `NAME was tagged!` or `NAME was tagged out of bounds!`.
- Normal tag and `tag_policy.result == "convert"` use `player_tagged`.
- Out-of-bounds auto-tag uses `player_tagged_out_of_bounds`.
- Overlay duration is 2 seconds; simultaneous tags queue FIFO.
- Overlay does not capture input and respects Reduce Motion.
- Existing event log, iOS live-update pill, and event prose remain unchanged.
- Do not infer tags from player status and do not parse names from prose.
- Do not add coordinates, secrets, or sensitive data to events.

---

### Task 1: Structured server event contract

**Files:**
- Modify: `server/app/engine/modules/tag_policy.py`
- Modify: `server/app/engine/modules/zone_policy.py`
- Modify: `server/app/realtime/manager.py`
- Modify: `server/app/realtime/ws.py`
- Test: `server/tests/engine/test_tag.py`
- Test: `server/tests/engine/test_zone_policy.py`
- Test: `server/tests/sim/test_location_broadcast.py`

**Interfaces:**
- Produces event fields `announcement: str | None` and `subject_name: str | None`.
- The values are copied from `GameEvent.payload` into live and reconnect event envelopes.

- [ ] Add failing engine assertions for `announcement` and `subject_name` on normal, convert, and out-of-bounds tags.
- [ ] Add a failing WebSocket test proving every connected player receives the structured fields.
- [ ] Run the focused tests and confirm the expected missing-field failures.
- [ ] Add the structured payload fields at both engine emission sites.
- [ ] Centralize realtime event serialization so live broadcasts and replay use the same fields.
- [ ] Run focused server tests, full `pytest -q`, and `ruff check .`.
- [ ] Commit the server contract.

### Task 2: iOS queue and full-screen overlay

**Files:**
- Create: `ios/Manhunt/TagAnnouncementOverlay.swift`
- Modify: `ios/Manhunt/Networking/DTOs.swift`
- Modify: `ios/Manhunt/Networking/GameSocket.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift`
- Modify: `ios/Manhunt/LiveGameView.swift`
- Test: `ios/ManhuntTests/LiveHudAndPresetsTests.swift`

**Interfaces:**
- Consumes WebSocket fields `seq`, `announcement`, and `subject_name`.
- Produces `TagAnnouncement` with stable event sequence/id, exact text, and FIFO presentation.

- [ ] Add failing decoding and queue tests for normal tag, out-of-bounds tag, unrelated events, FIFO order, and expiry.
- [ ] Run the selected XCTest cases and confirm failure.
- [ ] Decode a typed live event rather than extending `BannerDTO` with unrelated fields.
- [ ] Keep the existing live-update pill by adapting the typed event back to its current text/tone fields.
- [ ] Implement queue advancement in `AppStore`; each item remains current for 2 seconds.
- [ ] Build `TagAnnouncementOverlay` with centered text, red edge flash, no hit testing, Reduce Motion behavior, accessibility status text, and warning haptic.
- [ ] Place the overlay above `LiveGameView`.
- [ ] Run selected and full iOS tests on iPhone 16 Pro / iOS 18.4.
- [ ] Commit iOS support.

### Task 3: Web queue and full-screen overlay

**Files:**
- Create: `web/src/game/tagAnnouncements.ts`
- Create: `web/src/game/TagAnnouncementOverlay.tsx`
- Create: `web/src/game/TagAnnouncementOverlay.test.tsx`
- Modify: `web/src/api/ws.ts`
- Modify: `web/src/api/ws.test.ts`
- Modify: `web/src/App.tsx`
- Modify: `web/src/App.test.tsx`
- Modify: `web/src/screens/LiveMap.tsx`
- Modify: `web/src/styles.css`

**Interfaces:**
- Consumes the same structured WebSocket fields as iOS.
- `App` owns the FIFO queue so back-to-back socket callbacks cannot be lost to React batching.
- `LiveMap` renders only the current item.

- [ ] Add failing socket, reducer/queue, and overlay tests.
- [ ] Run focused Vitest tests and confirm failure.
- [ ] Expand the typed WebSocket event and preserve sequence deduplication.
- [ ] Implement a pure queue reducer/helper and wire `socket.onEvent` in `App`.
- [ ] Advance the queue every 2 seconds while the live screen is mounted; clear it on leave/end.
- [ ] Render a non-interactive accessible overlay with reduced-motion CSS.
- [ ] Run focused tests, full `npm test`, and the web build/typecheck.
- [ ] Commit web support.

### Task 4: Documentation and verification

**Files:**
- Modify: `docs/agent/project-context.md`

- [ ] Record the structured tag-announcement product contract in project context.
- [ ] Run server `pytest -q && ruff check .`.
- [ ] Run web `npm test` and build/typecheck.
- [ ] Run the complete iOS suite on iPhone 16 Pro / iOS 18.4.
- [ ] Verify `git diff` contains no secrets, coordinates, generated build products, or plan/spec edits beyond the committed documents.
- [ ] Commit documentation, push `cursor/seeker-reveal-c6fb`, and update/create its PR.
