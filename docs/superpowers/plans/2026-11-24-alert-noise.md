# Alert Noise Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show one live alert at a time for 4 seconds, with the rest waiting in a priority queue so nothing is lost. Higher-priority alerts jump ahead of lower ones in that queue. Also stop web banners from shrinking the map, hide the "Warmth is hidden from you." line, and stop showing a player their own "sent a last fix" alert.

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
- Queue rules. **Superseded 2026-11-25 by the user: never drop an alert the player has not seen.**
  - No cap, no expiry, and no trim after the app returns from the background. The earlier rules (a cap of 8, a 30 s expiry, at most 3 after background) are removed.
  - While nobody can look (the app is in the background, the tab is hidden, or the alert surface is covered), the 4 s clock stops. Alerts keep queueing. When the surface is visible again, the showing alert restarts its full 4 s and the queue carries on in priority order.
  - Coalesce duplicates: the same subject and type collapses to one entry with its latest words. This is the only merge. Confirmed by the user on 2026-11-25: a repeat of the same news (for example 53 "went dark" events for one player) is one entry.
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

- [x] Failing tests: a second same-priority alert waits, then shows after 4 s; a lower-priority alert waits behind a higher one; a higher-priority alert interrupts a lower one and the interrupted one shows afterward; nothing is lost.
- [x] Failing tests for the queue rules: no cap and no expiry (every queued alert is shown eventually, even after ten minutes); a higher-priority alert jumps ahead of lower ones; duplicates coalesce; backgrounding stops the clock and loses nothing.
- [x] Failing test: ten events in one second are shown one after another in priority order, and the sequence ends cleanly.
- [x] Route the safety "went dark" banners, the live-update pill, and the ping flash through the presenter.
- [x] Inject a clock so tests do not sleep.

### Task 2: Web banners overlay the map

**Files:**
- Modify: `web/src/screens/LiveMap.tsx`, `web/src/screens/LiveMap.css` (`.banners`)
- Create: `web/src/game/alertQueue.ts` (a pure queue shared by a `useAlert` hook)
- Test: Vitest for the queue and the hook, plus a CSS check that `.banners` is `position: absolute`

- [x] Failing tests for `alertQueue` with the same rules as iOS (priority, interrupt and resume, no cap and no expiry, coalescing, hidden-tab hold, 4 s timing with fake timers).
- [x] Change `.banners` from normal flow to an overlay anchored at the top of the map. Verify the map height no longer changes when an alert appears.
- [x] Test at a small phone viewport and in landscape. The map must stay full height.

### Task 3: Hide the warmth line

**Files:**
- Modify: `ios/Manhunt/Domain/HintCopy.swift`, `web/src/game/hintLine.ts`
- Test: existing hint tests

- [x] Failing tests: the hidden-warmth case returns no line (nil or empty) instead of "Warmth is hidden from you."
- [x] Update the callers so the hint area collapses entirely when there is no text, with no empty gap.
- [x] Search both clients for the string with `rg "Warmth is hidden"` and make sure no copy remains.

### Task 4: Do not announce your own last fix

**Files:**
- Modify: `server/app/engine/session.py` (`record_location` emits `final_ping` for `flag == "final"`) and `server/app/engine/views.py` or the realtime event filter
- Modify: iOS and web event handlers as a fallback
- Test: `server/tests/engine/test_final_ping.py`

- [x] Failing test: the sender's own event stream does not include the "sent a last fix" alert, while other players still receive it.
- [x] Prefer a server-side `actor_player_id` check so replay and reconnect behave the same. If the event model lacks the actor, add it. Do not match on name text.
- [x] Failing client test that the alert is not shown when `player_id` equals the local player id, as a safety net.
- [x] Check `AppStore.sendFinalPing` so opening the app does not fire it repeatedly.

## Later (human gate, not in this pass)

- `HUMAN GATE TODO:` **Sound effects for ping and tag.** An agent must not pick, generate, or download audio. A person decides and approves first. Do not start this until the user says so. Items for the human to settle:
  - Choose or commission the sounds (a ping cue and a tag cue). Confirm each file has a license that allows use in a shipped app, and record the source and license in the repo.
  - Decide silent-switch behavior. Suggested: respect the iPhone ring/silent switch and use an ambient audio category so music or podcasts keep playing.
  - Decide volume and length (short, under about one second) and whether a haptic replaces the sound when muted.
  - Decide whether players get a mute setting in settings, and whether hiders and seekers hear the same cue.
  - Web: browsers block audio until a user gesture. Decide how the web client unlocks it, or leave web silent.
  - After approval, an agent implements playback behind a setting, with tests for the mute setting and no playback during Reduce Motion alternatives if the user wants that. Keep the tag cue in step with the existing tag announcement overlay.

## Edge Cases To Cover

- Ten events in one second: all are shown in priority order, one at a time.
- A tag alert arrives while a ping flash is showing: the tag takes the slot, the ping flash returns afterward.
- Alert arrives while another is fading out.
- App returns from background with queued events: all are shown, one at a time, in priority order. The showing alert restarts its 4 s.
- A hidden-warmth hint combined with a real hint on the same screen.
- Screen reader: announce each alert once, including a resumed one.

## Done When

- iOS never shows two alerts at once, each lasts 4 seconds, and lower-priority alerts wait in the queue instead of disappearing. No alert is dropped before it has been seen.
- Web alerts overlay the map and never shrink it.
- No "Warmth is hidden from you." text anywhere.
- A player does not see their own last-fix alert, and others still do.
- The sound-effects gate is recorded and untouched.

## Verification (2026-11-25)

Audit of the tree against this plan. Most of it landed in `0450362` (and `b79e1ae`) before this pass, with every box still empty. Only the `sendFinalPing` regression test and the `FakeGameService.finalFlagCount` counter were new here. Nothing is committed. The cap, the 30 s expiry, and the background trim were removed later the same day (see below).

| Item | Evidence |
|---|---|
| iOS presenter, queue rules, 10-events-in-1-s, injected clock | `AlertPresenterTests` (all of it); `AlertQueue` takes `now`, no sleeps |
| Web queue and hook | `alertQueue.test.ts`, `useAlert.test.ts` |
| `.banners` overlays the map | `LiveMapCss.test.ts` pins `position: absolute`, a zero-height `.alert-anchor`, `pointer-events: none` |
| Map height does not change when an alert shows | Real-browser harness, not the live app: the real `LiveMap.css` around a copy of the `LiveMap.tsx` chrome (top bar, HUD, anchor, map, dock). Map height was identical with and without an alert, including a long wrapped one, at 375x667 portrait (476.9 px) and 667x375 landscape (184.9 px, no page overflow). Not measured: 320x568 (probe blocked), and no run against a real game screen |
| Warmth line hidden | `testHiderSeesASeekerHintAndNoLineAtAllWhenWarmthIsHidden` (`Phase3Tests`), `hintLine.test.ts` ("shows no line at all when the warmth is hidden"). `rg "Warmth is hidden"` finds no code or copy, only this plan |
| Own last fix not announced | `server/tests/engine/test_final_ping.py` (event flag, broadcast, replay, timeline), keyed on `player_id` with `hide_from_actor`, not on text. iOS safety net: `testYourOwnLastFixAlertIsNotShownButAnotherPlayersIs`. Web never turns events into alerts, so it has nothing to filter |
| Final ping not repeated on open | `testFinalPingFiresOncePerBackgroundStayNotOnReturn` |

Suites run on this branch: server `pytest -q` 338 passed and `ruff check .` clean (`tests/load/test_thirty_player_stress.py` fails inside the Cursor sandbox because it shells out to `ps`, which the sandbox blocks: `PermissionError: Operation not permitted: 'ps'`. It passes outside the sandbox. It is not a code flake); web `npm test` 306 passed and `npm run build` OK; iOS `xcodebuild test` 291 tests, 0 failures, on iPhone 16 Pro / iOS 18.4 (after the review fixes and the no-drop change below).

Not done, by design: the sound-effects human gate (untouched), the park playtest, and a check of the alert queue against a real game on a phone.

### Code review follow-up (2026-11-25)

A read-only reviewer subagent went over the alert-noise code. Each finding was checked against the code before acting.

Fixed, each with a test written first:

- iOS `AlertPresenter.schedule()` re-armed the 4 s timer on every enqueue, so a steady trickle of events pinned one alert on screen and starved the queue. It now keeps a timer already armed for the same wake time. `testAnEnqueueMidSlotDoesNotRestartTheVisibleAlertsTimer`.
- iOS `PingFlashOverlay` sat after `return` in `LiveGameView.body` and was never mounted, so the ping flash and haptic never ran. The compiler said so (`code after 'return' will never be executed`). It is now an `.overlay` on the ZStack, and both warnings are gone. This was a bug from `c19e3dd`, before this plan. No unit test can see it. **Not checked on a device or simulator screen.**
- `release` shifted alerts that arrived during a hold into the future, on both clients. They now count as 0 s waited. `testAnAlertQueuedDuringAHoldHasWaitedZeroSecondsOnRelease` and the web `treats an alert queued during a hold as having waited 0 s on release`.
- iOS `onShow` (flash and haptic) fired while the surface was suspended and again on release. It now fires once, when the alert is seen. `testOnShowWaitsForTheSurfaceAndFiresOnceNotTwice`.

Not changed, for the user to decide:

- Cap eviction: no longer applies. The user removed the cap on 2026-11-25.
- `aria-live` flips between `polite` and `assertive` on one node in `LiveMap.tsx`. This may make VoiceOver miss an announcement. It needs a screen reader to verify, so it was left alone. TODO: test with VoiceOver on iOS Safari before changing the markup.
- `store.note` can show a pill while a ping flash holds the slot. Hiding it would drop the note, since notes are not queued. Left as is.
- Smaller notes not acted on: web does not pause alerts behind the safety-disclaimer modal, `seenBannerIDs` is not cleared when a game ends, web routes `danger` banners as alerts and iOS does not, and the ended-game `/events` payload and crash-recovery path of `hide_from_actor` have no direct assertion.

### No unseen alert is dropped (2026-11-25)

The user said: do not drop unseen alerts, queue them, and let a higher-priority alert jump the queue. Done on both clients:

- Removed the cap of 8, the 30 s expiry, and the "show at most 3 after background" trim, plus the per-entry wait timestamps that only served expiry. Higher priority still takes the slot at once and still sorts ahead of lower priority in the queue.
- Because the old background trim is gone, the clock stops while nobody can see the alerts. iOS: `AlertPresenter.setBackgrounded`, driven by `AppStore.handleScenePhase`, alongside the existing surface hold. Web: `useAlert` holds while `document.visibilityState` is `hidden`. On return the showing alert restarts its full 4 s with a new `showID`, so it is announced again.
- Tests: `testThereIsNoCapEveryQueuedAlertIsShownEventually`, `testAnAlertThatWaitsForTenMinutesIsStillShown`, `testAHigherPriorityAlertJumpsAheadOfEverythingLowerInTheQueue`, `testBackgroundingStopsTheClockAndNothingIsLostOnReturn`, `testTheClockStaysStoppedUntilBothSurfaceAndAppAreVisible`; web `has no cap`, `still shows an alert that waited ten minutes`, `lets a higher-priority alert jump ahead`, and `stops the clock while the tab is hidden and loses nothing when it returns`.
- Not verified: the new Swift tests were not run red first (the web ones were). Nothing was run on a device. A long hidden-tab or background stay now means a long run of alerts on return, one per 4 s. That is what was asked for, but it may feel like a wall after a long absence. TODO: playtest it.
- Still merged: a repeat of the same subject and type (for example 53 "went dark" events for one player) is one entry. The user confirmed this on 2026-11-25.
- Kept as is: a higher-priority alert still interrupts the one showing. The user confirmed on 2026-11-25 that a tag takes priority, so a tag interrupts a ping flash and does not wait for its 4 s.

### Review items, resolved (2026-11-25)

Each remaining item from the reviewer was checked against the code:

- Fixed, test first: the web "Play safely" gate sits over a mounted `LiveMap` and did not stop the alert clock, so alerts ran out behind it. `LiveMap` now pauses on `holdPresence` (`does not use up an alert while the safety gate covers the map`, seen failing first). iOS had the same gap for its full-page scanner sheet and the "Leave this hunt?" and "Play safely" alerts. The medium-detent sheets (leaderboard, log, demo, code) leave the top of the map visible, so they were left alone. The rule is `AlertSurface.isVisible` (`testTheAlertSurfaceIsHiddenByAMapPickAFullPageSheetOrABlockingAlert`, seen failing first). **The sheet-versus-pill judgment was not checked on a screen.**
- Added, passes: `/events` strips `hide_from_actor` and `actor_id` from what another player receives (assertions in `test_reconnect_replay_and_timeline_also_hide_it_from_the_sender`). That was a gap in coverage, not a bug.
- Reviewer was wrong, no change: "`recovery.py` replays `hide_from_actor`". Replay never re-creates events (`session.py` returns early while `replaying`), and nothing reloads stored rows into `event_log`. After a restart the WebSocket catch-up has nothing to send, and the timeline filters on the stored payload flag, which is tested. A test built on the reviewer's premise failed, and was removed.
- Reviewer was wrong, no change: `seenBannerIDs` is not left stale after a game ends. `enqueueNewSafetyBanners` rebinds it on every view (`defer { seenBannerIDs = current }`).
- Not acted on, same-key different-priority coalescing: the key includes the event type, so one key always has one priority. Nothing calls it the other way. YAGNI.
- Not acted on, `store.note` beside a ping flash: hiding the note would lose it, because notes are not queued.
- Not acted on, `aria-live` flipping between polite and assertive: plausible, but it cannot be checked without VoiceOver on iOS Safari. TODO: test it on a device before restructuring.
- Not acted on, minor: duplicate "Tag accepted." note and toast on web, `danger` banner routing differing between clients (no server module sends one), and a mounted guard in `useAlert`.

