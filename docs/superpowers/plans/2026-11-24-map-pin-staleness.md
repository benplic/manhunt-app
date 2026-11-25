# Map Pin Staleness Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map pins and fix bars share one staleness rule: a fix older than two ping intervals is stale. Show that on the map with dimmed opacity. When you are eliminated, show only your own pin. Route the "You're out" nudge through the alert queue on iOS (web already does).

**Architecture:** Pure helpers on iOS (`PinStaleness`) and web (`pinStaleness.ts`) own the interval count and the bar→opacity table. `FixFreshness` / `fixFreshness` call into them for bar thresholds. Map renderers read wall-clock age from each pin's `at` timestamp.

**Tech Stack:** SwiftUI/XCTest on iOS 18.4, React/TypeScript with Vitest and Leaflet.

Source: playtest logs of 2026-11-23 and `FixFreshness` TODOs left for this plan. Related: `2026-11-24-alert-noise.md` ("You're out" uses the queue).

## Global Constraints

- Staleness is **wall-clock age of the fix**, never game seconds.
- Two ping intervals = stale = 2 fix bars = pin opacity 0.5 (named constants, shared).
- Do not commit, push, or deploy. Stop for user review when the plan is done.

---

### Task 1: Shared staleness helper

**Files:**
- Create: `ios/Manhunt/Domain/PinStaleness.swift`, `web/src/map/pinStaleness.ts`
- Modify: `ios/Manhunt/Domain/FixFreshness.swift`, `web/src/game/fixFreshness.ts`
- Test: `ios/ManhuntTests/RosterLobbyAvatarTests.swift` (`PinStalenessTests`), `web/src/map/pinStaleness.test.ts`

- [x] `staleAfterIntervals = 2` and bar thresholds match existing fix-bar tests.
- [x] `pinOpacity(forBars:)` table: 4→1, 3→0.88, 2→0.5, 1→0.45, 0→0.4.
- [x] Remove FixFreshness TODOs; both clients import the shared constant.

### Task 2: Dim stale pins on the map

**Files:**
- Modify: `ios/Manhunt/HuntMap.swift`, `ios/Manhunt/VisualModels.swift`, `ios/Manhunt/Store/AppStore.swift`
- Modify: `web/src/map/pins.ts`, `web/src/screens/LiveMap.tsx`
- Test: `web/src/map/pins.test.ts`

- [x] Pass fix timestamp, kind, and status on each visual player / `MapPin`.
- [x] iOS: timeline stays alive while people are on the map so opacity can age.
- [x] Web: 1 Hz clock when computing pins; Leaflet `setOpacity` on each marker.
- [x] Opacity matches fix bars for the same fix (stale → 0.5).

### Task 3: Eliminated viewer sees only their pin

**Files:**
- Modify: `ios/Manhunt/Store/AppStore.swift` (`livePeople`), `web/src/map/pins.ts`
- Test: `web/src/map/pins.test.ts`, existing `viewerExpectsFix` tests

- [x] When `you.status == eliminated`, drop every other player's pin.
- [x] Fix bars already hide teammates; map filtering matches.

### Task 4: "You're out" on the alert queue (iOS)

**Files:**
- Modify: `ios/Manhunt/Store/AppStore.swift` (`apply`), `ios/Manhunt/LiveGameView.swift`
- Test: existing `LiveMap.test.tsx` (web), iOS alert queue behavior via `apply` + `AlertPresenter`

- [x] Enqueue `out:self` at tag-or-bounds priority (same text as web).
- [x] Remove the duplicate stackable banner; keep the dock waiting card.

## Done When

- A pin older than two ping intervals renders at 0.5 opacity on iOS and web.
- Fix bars and pin opacity stay in lockstep.
- An eliminated player sees only their own pin.
- iOS "You're out" goes through `AlertPresenter`, not a second banner.

## Review follow-up (2026-11-25)

- iOS `out:self` gated on transition into `eliminated` (`AppStore.apply`), not every snapshot — matches web `youStatus` effect. Tests: `testEliminatedAlertEnqueuesOnceNotEverySnapshot`, `testLivePeopleShowsOnlyYouWhenEliminated`.

## Verification (2026-11-25)

Run locally:

- `cd web && npm test`
- `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`

Key tests: `PinStalenessTests`, `pinStaleness.test.ts`, `pins.test.ts`, `fixFreshness.test.ts`, `FixFreshnessTests`, `LiveMap` "you're out".
Run on a Mac before merge (2026-11-25, iPhone 16 Pro / iOS 18.4, Thread Sanitizer on): iOS 296 passed, web 311 passed and `npm run build` clean, server 338 passed and `ruff check .` clean. Nothing was run on a device.
