# Alert Noise Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show one live alert at a time for 4 seconds, with the rest waiting in a priority queue so nothing is lost. Also stop web banners from shrinking the map, hide the "Warmth is hidden from you." line, and stop showing a player their own "sent a last fix" alert.

**Architecture:** A small alert presenter with one visible slot and a priority queue replaces the stacked banners on both clients. Persistent state lives on the pin and in the leaderboard, never in the alert area. One server change skips the last-fix event for its sender.

**Tech Stack:** SwiftUI/XCTest on iOS 18.4, React/TypeScript with Vitest and CSS, FastAPI/Python with pytest.

Source: playtest logs of 2026-11-23 (PS95VZ emitted 53 signal-lost events) and user playtest feedback. Related plans: `2026-11-24-connection-health.md` (socket meter tap), `2026-11-24-map-pin-staleness.md` ("You're out" state uses this queue), `2026-11-24-late-join-queue.md` (host join-request alert).

## Global Constraints

- Exactly one alert is visible at a time, for **4 seconds**. Respect Reduce Motion.
- Lower-priority alerts are **queued, not overwritten**. Decided by the user.
- Priority order, highest first: (1) tag and out-of-bounds, (2) safety "went dark", (3) ping flash, (4) live-update pill.
  - A higher-priority alert that arrives while a lower one is showing takes the slot right away. The interrupted alert goes back to the front of its priority tier and shows again afterward with its full 4 seconds, unless it has expired.
  - A lower-priority alert that arrives while a higher one is showing waits in the queue.
  - Within one priority, alerts are first in, first out.
- Queue rules so it cannot become a wall of stale news:
  - Maximum 8 queued alerts. When full, drop the oldest lowest-priority one.
  - Drop an alert that has waited longer than 30 seconds without being shown. TODO: confirm the 30 s expiry with the user.
  - Coalesce duplicates: the same subject and type within the queue collapses to one entry.
  - After the app returns from the background, show at most the 3 highest-priority queued alerts, in order, and discard the rest.
- The tag announcement overlay from `2026-11-23-tag-announcements.md` keeps its own FIFO queue and stays unchanged.
- Alerts never capture input and never resize the map.
- Do not commit, push, or deploy. Stop for user review when the plan is done.

---

### Task 1: Alert presenter with a priority queue (iOS)

**Files:**
- Create: `ios/Manhunt/AlertPresenter.swift`
- Modify: `ios/Manhunt/LiveGameView.swift` (top bar and banner stack), `ios/Manhunt/Store/AppStore.swift` (`recordLiveEvent`, `LiveUpdate`), `ios/Manhunt/PingFlashOverlay.swift`
- Test: `ios/ManhuntTests/AlertPresenterTests.swift`

**Interfaces:**
- `AlertPresenter.enqueue(_ alert: LiveAlert)`. `LiveAlert` has `id`, `text`, `tone`, `priority`, `subjectKey`, `createdAt`.
- `AlertPresenter.current: LiveAlert?` is what the UI renders. The presenter owns the 4 second timer and takes an injected clock.

- [ ] Failing tests: a second same-priority alert waits, then shows after 4 s; a lower-priority alert waits behind a higher one; a higher-priority alert interrupts a lower one and the interrupted one shows afterward; nothing is lost until the cap or expiry applies.
- [ ] Failing tests for the queue rules: cap of 8 drops the oldest lowest-priority; expired alerts (30 s) are skipped; duplicates coalesce; background return shows at most 3.
- [ ] Failing test: ten events in one second are shown one after another in priority order, and the sequence ends cleanly.
- [ ] Route the safety "went dark" banners, the live-update pill, and the ping flash through the presenter.
- [ ] Inject a clock so tests do not sleep.

### Task 2: Web banners overlay the map

**Files:**
- Modify: `web/src/screens/LiveMap.tsx`, `web/src/screens/LiveMap.css` (`.banners`)
- Create: `web/src/game/alertQueue.ts` (a pure queue shared by a `useAlert` hook)
- Test: Vitest for the queue and the hook, plus a CSS check that `.banners` is `position: absolute`

- [ ] Failing tests for `alertQueue` with the same rules as iOS (priority, interrupt and resume, cap, expiry, coalescing, 4 s timing with fake timers).
- [ ] Change `.banners` from normal flow to an overlay anchored at the top of the map. Verify the map height no longer changes when an alert appears.
- [ ] Test at a small phone viewport and in landscape. The map must stay full height.

### Task 3: Hide the warmth line

**Files:**
- Modify: `ios/Manhunt/Domain/HintCopy.swift`, `web/src/game/hintLine.ts`
- Test: existing hint tests

- [ ] Failing tests: the hidden-warmth case returns no line (nil or empty) instead of "Warmth is hidden from you."
- [ ] Update the callers so the hint area collapses entirely when there is no text, with no empty gap.
- [ ] Search both clients for the string with `rg "Warmth is hidden"` and make sure no copy remains.

### Task 4: Do not announce your own last fix

**Files:**
- Modify: `server/app/engine/session.py` (`record_location` emits `final_ping` for `flag == "final"`) and `server/app/engine/views.py` or the realtime event filter
- Modify: iOS and web event handlers as a fallback
- Test: `server/tests/engine/test_final_ping.py`

- [ ] Failing test: the sender's own event stream does not include the "sent a last fix" alert, while other players still receive it.
- [ ] Prefer a server-side `actor_player_id` check so replay and reconnect behave the same. If the event model lacks the actor, add it. Do not match on name text.
- [ ] Failing client test that the alert is not shown when `player_id` equals the local player id, as a safety net.
- [ ] Check `AppStore.sendFinalPing` so opening the app does not fire it repeatedly.

## Later (human gate, not in this pass)

- `HUMAN GATE TODO:` **Sound effects for ping and tag.** An agent must not pick, generate, or download audio. A person decides and approves first. Do not start this until the user says so. Items for the human to settle:
  - Choose or commission the sounds (a ping cue and a tag cue). Confirm each file has a license that allows use in a shipped app, and record the source and license in the repo.
  - Decide silent-switch behavior. Suggested: respect the iPhone ring/silent switch and use an ambient audio category so music or podcasts keep playing.
  - Decide volume and length (short, under about one second) and whether a haptic replaces the sound when muted.
  - Decide whether players get a mute setting in settings, and whether hiders and seekers hear the same cue.
  - Web: browsers block audio until a user gesture. Decide how the web client unlocks it, or leave web silent.
  - After approval, an agent implements playback behind a setting, with tests for the mute setting and no playback during Reduce Motion alternatives if the user wants that. Keep the tag cue in step with the existing tag announcement overlay.

## Edge Cases To Cover

- Ten events in one second: all are shown in priority order, one at a time, within the cap.
- A tag alert arrives while a ping flash is showing: the tag takes the slot, the ping flash returns afterward.
- Alert arrives while another is fading out.
- App returns from background with queued events: at most 3 highest-priority are shown.
- A hidden-warmth hint combined with a real hint on the same screen.
- Screen reader: announce each alert once, including a resumed one.

## Done When

- iOS never shows two alerts at once, each lasts 4 seconds, and lower-priority alerts wait in the queue instead of disappearing.
- Web alerts overlay the map and never shrink it.
- No "Warmth is hidden from you." text anywhere.
- A player does not see their own last-fix alert, and others still do.
- The sound-effects gate is recorded and untouched.
