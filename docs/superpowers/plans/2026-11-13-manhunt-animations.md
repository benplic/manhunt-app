# Manhunt animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the live clock, progress bar and player pins move smoothly in the PARK42 demo, flash the screen on a ping, preview and animate the zone shrink, and give custom buttons a press animation plus haptic.

**Architecture:** The server adds one field (`timers.zone.interval_s`). Everything else is client-side. `ClockLead` extrapolates the 1 Hz snapshots, `PlayerGlide` interpolates pins, `ZoneShrinkPlan` turns the shrink countdown into a radius and a dashed preview, `PingDetector` spots the reveal countdown wrapping, and `HuntPressStyle` is the shared button feel. `HuntMap` and `LiveHUD` wrap their content in `TimelineView` (30 Hz) so only the live screen redraws per frame. The editor never opts in.

**Tech Stack:** SwiftUI on iOS 18 (`TimelineView`, `KeyframeAnimator`, `sensoryFeedback`, MapKit), XCTest. FastAPI and pytest for the one server field.

## What I found (why the current build stutters)

- The server ticks once per second (`tick_loop` sleeps 1 s, then broadcasts). The phone gets one snapshot per second, so `PhaseClock` shows integer seconds that step. `HuntProgressBar` follows the same steps.
- Demo speed 2x/5x/10x runs N engine ticks per second. Timers and bot positions jump by N between snapshots.
- `HuntMap` draws each pin at the last snapshot coordinate, so pins teleport once per second.
- `HuntMap` never draws the shrinking zone from `timers.zone`. It draws the static `boundaryCircle`, which the server shrinks instantly in one step (`ZoneShrinkModule.on_tick`). There is no dashed next-zone ring today.
- The server only sends `radius_m`, `next_radius_m` and `shrinks_in_s`. The client cannot know "halfway between shrinks" without the interval, so the server must send it.
- The server `reveal` event is emitted only when pins were added, so hot/cold pulses and all-ghost pulses never fire it. Detecting the `next_reveal_in_s` wrap on the client is more reliable.
- Buttons are bare `Button` plus `.buttonStyle(.plain)` in 13 files. The only haptics today are the live-update pill and the out-of-bounds warning.

## Assumptions (no clarifying channel in this run; veto any at confirmation)

1. "Demo lobby" means the PARK42 sample game with bots, host speed 1x/2x/5x/10x and virtual walking. The fixes apply to every live game.
2. "Ping" is the reveal pulse (HUD "Ping 0:57"). Everyone in the match gets the flash. Hiders get red edges and a warning haptic ("you were exposed"). Seekers get yellow edges and a medium impact.
3. The dashed line is a dashed circle at `next_radius_m` that fades in once half of the shrink interval remains.
4. The shrink animation is the solid yellow ring contracting over the last quarter of the interval, landing on the dashed ring at the exact moment the server applies the shrink. I chose "before" over "after" the server shrink. A ring drawn larger than the real boundary after the shrink would show a player as safe while the server runs the out-of-bounds penalty. Early contraction only ever draws tighter than reality. If you meant "start animating after the shrink", only `ZoneShrinkPlan.visual` changes.
5. Haptics fire on press-down for custom-styled buttons. System-owned controls (alerts, confirmation dialogs, context menus, toolbar Done, Sign in with Apple, Toggle, Stepper, Picker) already animate and buzz, so they stay untouched. Haptics cannot be verified in the simulator.

## Approaches considered

- **Pins.** (A) Recompute `Map` content at 30 Hz inside `TimelineView`. Chosen: one code path for pins and the contracting ring. Risk is per-frame content diffing. (B) Float pins over the map with `MapReader.convert`: cheaper per frame, but the ring needs a meters-to-points conversion, z-order is wrong, and panning forces relayout. (C) Bridge `MKMapView`: best performance, large rewrite. Fallback is B if Instruments on a device shows heavy CPU (Task 3, Step 7).
- **Timer.** (Chosen) Extrapolate between snapshots with a one-tick cap. Rejected: send server ticks at 10 Hz. That is 10x websocket traffic and the wrong layer for a presentation problem.

## Global Constraints

- Distances use 111,320 m per degree, not haversine. Use `ArenaGeometry.meters(from:to:)`.
- The engine does not call `datetime.now()` or the global `random`. The server change only adds a schedule field.
- `is_decoy` never goes out on the wire. No coordinates or tokens in logs.
- Code, comments and docs are English. Unfinished behavior gets a `TODO:` comment. Do not swallow exceptions.
- iOS deployment target is 18.0. New Swift files in `ios/Manhunt/` and `ios/ManhuntTests/` join the targets automatically (file-system synchronized groups). No `project.pbxproj` edit.
- This is not a remaining-benchmarks item. Do not edit the Open or Closed lists in `docs/superpowers/plans/2026-11-09-remaining-benchmarks.md`.
- Branch: `cursor/manhunt-animations-56c5` off `cursor/scoring-zones-hud-0d26`. The cloud harness mandates the `-56c5` suffix and overrides the `-2a9d` in AGENTS.md.
- The working tree already has Scott's uncommitted app-icon changes under `ios/Assets.xcassets/AppIcon.appiconset/`. Stage explicit paths only. Never `git add -A`.
- Do not open a PR or deploy unless Scott asks (AGENTS.md and his hard rules). The harness defaults to opening a PR, so flag that conflict in the final message instead of resolving it silently.
- Server check: `cd server && . .venv/bin/activate && pytest -q && ruff check .`
- iOS check: `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`. This machine has Xcode 26.2, the 18.4 runtime and a booted iPhone 16 Pro. Free disk was 7.4 GiB. If `xcodebuild` fails with "No space left on device", say so. Do not report a pass you did not see.
- Single-test form: append `-only-testing:ManhuntTests/<ClassName>`.

---

## File Structure

Create:
- `ios/Manhunt/Domain/ClockLead.swift`: rate, lead and anchor rules for extrapolating snapshots.
- `ios/Manhunt/Domain/PlayerGlide.swift`: per-player interpolation between snapshots.
- `ios/Manhunt/Domain/ZoneShrinkPlan.swift`: `ZoneShrinkVisual`, `ZoneShrinkPlan`, `ZoneShrinkClock`.
- `ios/Manhunt/Domain/PingDetector.swift`: spots a reveal pulse between two views.
- `ios/Manhunt/PingFlashOverlay.swift`: the full-screen flash and its haptic.
- `ios/Manhunt/ButtonFeedback.swift`: `HuntHaptic`, `HuntPressStyle`, `.huntPress(...)`.
- `ios/ManhuntTests/SmoothClockTests.swift`, `PlayerGlideTests.swift`, `ZoneShrinkPlanTests.swift`, `PingDetectorTests.swift`.
- `docs/superpowers/specs/2026-11-13-manhunt-animations-design.md` and `docs/superpowers/plans/2026-11-13-manhunt-animations.md`.

Modify:
- `server/app/engine/modules/zone_shrink.py`, `server/app/engine/views.py`, `server/tests/engine/test_zone_shrink.py`
- `ios/Manhunt/Networking/DTOs.swift`, `ios/Manhunt/Networking/FakeGameService.swift`
- `ios/Manhunt/Domain/PhaseClock.swift`, `ios/Manhunt/Store/AppStore.swift`
- `ios/Manhunt/LiveHUD.swift`, `ios/Manhunt/LiveGameView.swift`, `ios/Manhunt/HuntMap.swift`, `ios/Manhunt/LobbyView.swift`
- `ios/Manhunt/Components.swift`, `LiveControls.swift`, `HomeView.swift`, `CreateGameView.swift`, `ArenaEditorView.swift`, `DemoPanelView.swift`, `SignInView.swift`
- `ios/ManhuntTests/Fixtures.swift`

---

### Task 0: Branch and docs

- [ ] **Step 1:** `git checkout -b cursor/manhunt-animations-56c5`
- [ ] **Step 2:** Write the "What I found", "Assumptions" and "Approaches considered" sections of this plan to `docs/superpowers/specs/2026-11-13-manhunt-animations-design.md`. Write this whole plan to `docs/superpowers/plans/2026-11-13-manhunt-animations.md`. Do not touch the Cursor plan file under the agent store.
- [ ] **Step 3:** `git add docs/superpowers/specs/2026-11-13-manhunt-animations-design.md docs/superpowers/plans/2026-11-13-manhunt-animations.md && git commit -m "docs: add the animations design and plan"`

### Task 1: Server sends the shrink interval

**Files:**
- Modify: `server/app/engine/modules/zone_shrink.py` (`zone_shrink_schedule` return dict)
- Modify: `server/app/engine/views.py` (`_build_timers`, `zone_timer` dict)
- Modify: `ios/Manhunt/Networking/DTOs.swift` (`ZoneTimerDTO`), `ios/Manhunt/Networking/FakeGameService.swift` (`ZoneTimerDTO(` call, about line 571)
- Test: `server/tests/engine/test_zone_shrink.py`, `ios/ManhuntTests/ZoneShrinkPlanTests.swift` (created here, extended in Task 4)

**Interfaces:**
- Produces: JSON `timers.zone.interval_s` (int seconds between shrinks, `every * 60`, present whenever the zone timer is). Swift `ZoneTimerDTO.intervalS: Int?` (nil from older servers).

- [ ] **Step 1: Write the failing server tests.** In `test_zone_shrink.py` add `"interval_s": 60` to the three `["timers"]["zone"] == {...}` dict assertions (about lines 43, 76 and 89, including the floor case where `next_radius_m` is `None`). Append:

```python
def test_zone_timer_reports_the_shrink_interval() -> None:
    session, _ = make_session(
        arena=_circle_arena(400.0),
        overrides={
            "head_start": {"enabled": False},
            "zone_shrink": {
                "enabled": True,
                "every": 2,
                "shrink_to": 50,
                "min_radius_m": 50,
            },
        },
    )
    hider = uuid4()
    seeker = uuid4()
    session.add_player(hider, "Riley", True)
    session.add_player(seeker, "Jordan", False)
    session.set_role(hider, "hider")
    session.set_role(seeker, "seeker")
    session.start()

    assert build_view(session, hider)["timers"]["zone"]["interval_s"] == 120
```

- [ ] **Step 2:** `cd server && . .venv/bin/activate && pytest tests/engine/test_zone_shrink.py -q`. Expected: FAIL (missing `interval_s`).
- [ ] **Step 3: Implement.** In `zone_shrink_schedule`'s returned dict add `"interval_s": every_s,`. In `_build_timers`'s `zone_timer` dict add `"interval_s": schedule["interval_s"],`.
- [ ] **Step 4:** `pytest -q && ruff check .`. Expected: all pass, ruff clean.
- [ ] **Step 5: Failing Swift test.** Create `ios/ManhuntTests/ZoneShrinkPlanTests.swift`:

```swift
import XCTest
@testable import Manhunt

final class ZoneShrinkPlanTests: XCTestCase {
    func testZoneTimerDecodesTheShrinkInterval() throws {
        let json = #"{"radius_m": 210.0, "next_radius_m": 157.5, "shrinks_in_s": 42, "interval_s": 60}"#
        let zone = try JSONDecoder().decode(ZoneTimerDTO.self, from: Data(json.utf8))
        XCTAssertEqual(zone.intervalS, 60)
        let old = try JSONDecoder().decode(ZoneTimerDTO.self, from: Data(#"{"radius_m": 210.0}"#.utf8))
        XCTAssertNil(old.intervalS)
    }
}
```

Run `-only-testing:ManhuntTests/ZoneShrinkPlanTests`. Expected: FAIL (no member `intervalS`).

- [ ] **Step 6: Implement.** In `ZoneTimerDTO` add `var intervalS: Int? = nil` and `case intervalS = "interval_s"` in `CodingKeys`. In `FakeGameService.view()` pass `intervalS: 60`. Re-run the test (PASS), then the full iOS suite.
- [ ] **Step 7: Commit.** `git add server/app/engine/modules/zone_shrink.py server/app/engine/views.py server/tests/engine/test_zone_shrink.py ios/Manhunt/Networking/DTOs.swift ios/Manhunt/Networking/FakeGameService.swift ios/ManhuntTests/ZoneShrinkPlanTests.swift && git commit -m "feat: send the zone shrink interval to clients"`

### Task 2: Smooth clock, timer and progress bar

**Files:**
- Create: `ios/Manhunt/Domain/ClockLead.swift`
- Modify: `ios/Manhunt/Domain/PhaseClock.swift`, `ios/Manhunt/Store/AppStore.swift` (`MatchHandle`, `apply`), `ios/Manhunt/LiveHUD.swift`, `ios/Manhunt/LiveGameView.swift` (`topBar`, about line 204), `ios/Manhunt/LobbyView.swift` (demo countdown, about line 104), `ios/ManhuntTests/Fixtures.swift`
- Test: `ios/ManhuntTests/SmoothClockTests.swift`

**Interfaces:**
- Produces: `ClockLead.rate(snapshot: PlayerViewDTO?, paused: Bool) -> Double`; `ClockLead.seconds(rate: Double, anchoredAt: Date, now: Date) -> Double`; `ClockLead.anchor(previous: PlayerViewDTO?, previousAnchor: Date?, next: PlayerViewDTO, now: Date) -> Date`; `PhaseClock.init(snapshot:paused:locale:leadS:)` (`leadS` defaults to 0, so existing tests are unchanged); `MatchHandle.clockAnchorAt: Date`; `AppStore.apply(_:now:)`.

- [ ] **Step 1: Add the fixture** to `Fixtures.swift`:

```swift
static func liveView(
    phase: MatchPhase = .active,
    elapsed: Int = 0,
    timeLimitRemaining: Int? = 1800,
    nextReveal: Int? = 60,
    zone: ZoneTimerDTO? = nil,
    role: PlayerRole = .hider
) -> PlayerViewDTO {
    PlayerViewDTO(
        gameId: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
        joinCode: "PARK42",
        phase: phase,
        phaseRemainingS: phase == .headStart ? max(0, 60 - elapsed) : nil,
        gameElapsedS: elapsed,
        timeLimitRemainingS: timeLimitRemaining,
        timers: TimersDTO(
            headStartS: 60, timeLimitS: 1800, revealIntervalS: 60,
            nextRevealInS: nextReveal, zone: zone
        ),
        you: YouDTO(
            playerId: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
            role: role, status: .active, isHost: true,
            bounds: BoundsDTO(phase: "inside", remainingS: nil),
            safeZone: nil, points: 0
        ),
        players: [], reveals: [], banners: [], result: nil
    )
}
```

- [ ] **Step 2: Write the failing tests** in `SmoothClockTests.swift`:

```swift
import XCTest
@testable import Manhunt

final class SmoothClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testLeadGrowsWithTheRateAndStopsAtOneTick() {
        XCTAssertEqual(ClockLead.seconds(rate: 1, anchoredAt: t0, now: t0.addingTimeInterval(0.4)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(ClockLead.seconds(rate: 1, anchoredAt: t0, now: t0.addingTimeInterval(9)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ClockLead.seconds(rate: 5, anchoredAt: t0, now: t0.addingTimeInterval(9)), 5.0, accuracy: 1e-9)
        XCTAssertEqual(ClockLead.seconds(rate: 0, anchoredAt: t0, now: t0.addingTimeInterval(0.4)), 0)
        XCTAssertEqual(ClockLead.seconds(rate: 1, anchoredAt: t0, now: t0.addingTimeInterval(-3)), 0)
    }

    func testRateIsZeroUnlessTheMatchClockRuns() {
        XCTAssertEqual(ClockLead.rate(snapshot: nil, paused: false), 0)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .active), paused: false), 1)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .active), paused: true), 0)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .lobby), paused: false), 0)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .ended), paused: false), 0)
        var held = Fixtures.liveView(phase: .headStart)
        held.spawnLock = SpawnLockDTO(outside: false, zones: [], holding: true)
        XCTAssertEqual(ClockLead.rate(snapshot: held, paused: false), 0)
        var demo = Fixtures.liveView(phase: .active)
        demo.demo = DemoDTO(speed: 5, lobbyHold: false, seekerLock: "spawn_zone",
                            controlsEnabled: true, virtualLocation: nil, bots: [])
        XCTAssertEqual(ClockLead.rate(snapshot: demo, paused: false), 5)
    }

    func testAnchorMovesOnlyWhenTheServerClockMoves() {
        let tick = Fixtures.liveView(elapsed: 10)
        let later = t0.addingTimeInterval(0.6)
        XCTAssertEqual(ClockLead.anchor(previous: nil, previousAnchor: nil, next: tick, now: t0), t0)
        // A demo action reply carries the same game second and must not rewind the countdown.
        XCTAssertEqual(ClockLead.anchor(previous: tick, previousAnchor: t0, next: tick, now: later), t0)
        XCTAssertEqual(ClockLead.anchor(previous: tick, previousAnchor: t0,
                                        next: Fixtures.liveView(elapsed: 11), now: later), later)
        XCTAssertEqual(ClockLead.anchor(previous: tick, previousAnchor: t0,
                                        next: Fixtures.liveView(phase: .paused, elapsed: 10), now: later), later)
    }

    func testPhaseClockCountsDownBetweenSnapshots() {
        let view = Fixtures.liveView(
            elapsed: 100, timeLimitRemaining: 900, nextReveal: 12,
            zone: ZoneTimerDTO(radiusM: 310, nextRadiusM: 259, shrinksInS: 42, intervalS: 60)
        )
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(PhaseClock(snapshot: view, paused: false, locale: us).primaryClock, "15:00")
        let half = PhaseClock(snapshot: view, paused: false, locale: us, leadS: 0.5)
        XCTAssertEqual(half.primaryClock, "15:00")
        XCTAssertEqual(half.primaryProgress, 1 - 899.5 / 1800, accuracy: 1e-9)
        XCTAssertEqual(half.pingProgress, 1 - 11.5 / 60, accuracy: 1e-9)
        let full = PhaseClock(snapshot: view, paused: false, locale: us, leadS: 1.0)
        XCTAssertEqual(full.primaryClock, "14:59")
        XCTAssertEqual(full.pingClock, "0:11")
        XCTAssertEqual(full.zoneLine, "Zone 0.19 mi → 850 ft in 0:41")
        XCTAssertGreaterThan(full.primaryProgress, half.primaryProgress)
    }

    @MainActor
    func testApplyKeepsTheAnchorForAnOutOfCycleView() {
        let store = AppStore.makePreview()
        store.apply(Fixtures.liveView(elapsed: 10), now: t0)
        store.apply(Fixtures.liveView(elapsed: 10), now: t0.addingTimeInterval(0.6))
        XCTAssertEqual(store.match?.clockAnchorAt, t0)
        store.apply(Fixtures.liveView(elapsed: 11), now: t0.addingTimeInterval(1.0))
        XCTAssertEqual(store.match?.clockAnchorAt, t0.addingTimeInterval(1.0))
    }
}
```

- [ ] **Step 3:** Run `-only-testing:ManhuntTests/SmoothClockTests`. Expected: FAIL (build error, `ClockLead` not found).
- [ ] **Step 4: Implement `ClockLead`:**

```swift
import Foundation

/// Extrapolates the 1 Hz server snapshots so countdowns move every frame.
enum ClockLead {
    /// One server tick. Past this the clock holds and waits for the next snapshot, so a late
    /// snapshot never makes the display run backwards.
    static let maxWallSeconds: TimeInterval = 1.0

    /// Game seconds per wall second. Zero whenever the match clock is not running.
    static func rate(snapshot: PlayerViewDTO?, paused: Bool) -> Double {
        guard let snapshot, !paused else { return 0 }
        switch snapshot.phase {
        case .lobby, .paused, .ended: return 0
        case .headStart, .active: break
        }
        if snapshot.spawnLock?.holding == true { return 0 }
        return Double(max(1, snapshot.demo?.speed ?? 1))
    }

    /// Game seconds elapsed since the snapshot arrived, capped at one tick.
    static func seconds(rate: Double, anchoredAt: Date, now: Date) -> Double {
        guard rate > 0 else { return 0 }
        let wall = min(max(0, now.timeIntervalSince(anchoredAt)), maxWallSeconds)
        return wall * rate
    }

    /// New anchor time for an incoming view. Re-anchor only when the server clock moved.
    static func anchor(previous: PlayerViewDTO?, previousAnchor: Date?, next: PlayerViewDTO, now: Date) -> Date {
        guard let previous, let previousAnchor else { return now }
        let sameClock = previous.gameElapsedS == next.gameElapsedS
            && previous.phase == next.phase
            && previous.spawnLock?.holding == next.spawnLock?.holding
            && previous.demo?.speed == next.demo?.speed
        return sameClock ? previousAnchor : now
    }
}
```

- [ ] **Step 5: `PhaseClock`.** Add `leadS: Double = 0` as the last `init` parameter. Add `private static func left(_ seconds: Int, _ lead: Double) -> Double { max(0, Double(seconds) - lead) }`. In each timer branch compute `let left = Self.left(remaining, leadS)`, show `Self.clock(Int(left.rounded(.up)))`, and use `1.0 - left / Double(total)` for progress. Apply the same to `nextPing` (ping clock and progress) and `shrinksIn` (zone line and the `<= 60` imminent test). With `leadS == 0` every existing assertion in `LiveHudAndPresetsTests` still holds.
- [ ] **Step 6: `MatchHandle` and `apply`.** Add `var clockAnchorAt = Date()` to `MatchHandle` (memberwise default keeps the two test call sites compiling). Change to `func apply(_ view: PlayerViewDTO, now: Date = Date())` and replace the assignment:

```swift
let anchor = ClockLead.anchor(previous: match?.snapshot, previousAnchor: match?.clockAnchorAt, next: view, now: now)
match = MatchHandle(snapshot: view, qrToken: match?.qrToken, clockAnchorAt: anchor)
```

- [ ] **Step 7: `LiveHUD`.** Change the inputs to `snapshot: PlayerViewDTO?`, `paused: Bool`, `anchoredAt: Date`, `situation: LiveSituation`. Wrap the current body in a timeline and add digit transitions:

```swift
var body: some View {
    let rate = ClockLead.rate(snapshot: snapshot, paused: paused)
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: rate == 0)) { timeline in
        let lead = ClockLead.seconds(rate: rate, anchoredAt: anchoredAt, now: timeline.date)
        content(PhaseClock(snapshot: snapshot, paused: paused, leadS: lead))
    }
}
```

`content(_ clock:)` is the old body. On the clock `Text` and the "Ping" `Text` add `.contentTransition(.numericText(countsDown: true))` and `.animation(.snappy(duration: 0.2), value: <that text>)`. Leave `HuntProgressBar` without an animation modifier. It already follows the continuous progress, and an animation would lag it. In `LiveGameView.topBar` pass `snapshot: store.match?.snapshot, paused: store.paused, anchoredAt: store.match?.clockAnchorAt ?? Date()`. In `LobbyView` add `.contentTransition(.numericText(countsDown: true))` and `.animation(.snappy, value: seconds)` to the "Starts in" label.

- [ ] **Step 8:** Run `SmoothClockTests` (PASS), then the full iOS suite (the existing `testPhaseClockProgressHeadStartActiveAndDistances` must still pass).
- [ ] **Step 9: Commit** `ClockLead.swift`, `PhaseClock.swift`, `AppStore.swift`, `LiveHUD.swift`, `LiveGameView.swift`, `LobbyView.swift`, `Fixtures.swift` and `SmoothClockTests.swift` by explicit path. Message: `feat: extrapolate the live clock between snapshots`.

### Task 3: Smooth player movement

**Files:**
- Create: `ios/Manhunt/Domain/PlayerGlide.swift`
- Modify: `ios/Manhunt/HuntMap.swift`, `ios/Manhunt/LiveGameView.swift` (pass `glidePeople: true`)
- Test: `ios/ManhuntTests/PlayerGlideTests.swift`

**Interfaces:**
- Produces: `PlayerGlide.retarget(_ people: [VisualPlayer], now: Date)`, `PlayerGlide.point(for id: String, at now: Date) -> VisualPoint?`, `PlayerGlide.isSettled(at:) -> Bool`; `HuntMap.glidePeople: Bool = false`.

- [ ] **Step 1: Write the failing tests:**

```swift
import XCTest
@testable import Manhunt

final class PlayerGlideTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000)

    private func pin(_ id: String, x: Double, y: Double = 0) -> VisualPlayer {
        let p = Fixtures.meters(x: x, y: y)
        return VisualPlayer(id: id, name: id, role: .hider, isYou: false, isHost: false,
                            point: VisualPoint(latitude: p.latitude, longitude: p.longitude),
                            points: 0, earned: 0)
    }
    private func eastMeters(_ point: VisualPoint?) -> Double? { point.map { $0.longitude * 111_320 } }

    func testNewPlayerAppearsWhereItIs() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 40)], now: t0)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0))!, 40, accuracy: 0.01)
    }

    func testPinGlidesInAStraightLineOverTheSnapshotGap() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1)))!, 0, accuracy: 0.01)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1.5)))!, 5, accuracy: 0.01)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(2)))!, 10, accuracy: 0.01)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(9)))!, 10, accuracy: 0.01)
    }

    func testRetargetMidGlideStartsFromTheDrawnPoint() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        glide.retarget([pin("a", x: 20)], now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1.5)))!, 5, accuracy: 0.01)
    }

    func testUnchangedTargetDoesNotRestartTheGlide() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1.4))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1.5)))!, 5, accuracy: 0.01)
    }

    func testBigJumpTeleportsAndRemovedPlayersAreForgotten() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0), pin("b", x: 0)], now: t0)
        glide.retarget([pin("a", x: 400)], now: t0.addingTimeInterval(1))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1)))!, 400, accuracy: 0.01)
        XCTAssertNil(glide.point(for: "b", at: t0.addingTimeInterval(1)))
    }

    func testSettledOnlyAfterEveryGlideFinishes() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        XCTAssertFalse(glide.isSettled(at: t0.addingTimeInterval(1.5)))
        XCTAssertTrue(glide.isSettled(at: t0.addingTimeInterval(2.1)))
    }
}
```

- [ ] **Step 2:** Run `-only-testing:ManhuntTests/PlayerGlideTests`. Expected: FAIL (build error).
- [ ] **Step 3: Implement `PlayerGlide`:**

```swift
import Foundation

/// Keeps a pin moving between 1 Hz snapshots. Each new target starts a straight-line glide from
/// wherever the pin is drawn now, so it never snaps back and never overshoots. The display runs
/// about one snapshot behind the server, which is the price of never extrapolating.
struct PlayerGlide {
    static let minDuration: TimeInterval = 0.5
    static let maxDuration: TimeInterval = 1.25
    static let defaultDuration: TimeInterval = 1.0
    /// Longer jumps (role switch, demo skip) teleport instead of racing across the map.
    static let teleportMeters = 150.0

    private struct Track {
        var from: VisualPoint
        var to: VisualPoint
        var startedAt: Date
        var duration: TimeInterval
    }

    private var tracks: [String: Track] = [:]

    mutating func retarget(_ people: [VisualPlayer], now: Date) {
        var next: [String: Track] = [:]
        for person in people {
            guard let track = tracks[person.id] else {
                next[person.id] = Track(from: person.point, to: person.point, startedAt: now,
                                        duration: Self.defaultDuration)
                continue
            }
            if track.to == person.point {
                next[person.id] = track
                continue
            }
            let drawn = Self.position(of: track, at: now)
            let gap = ArenaGeometry.meters(
                from: GeoPoint(latitude: drawn.latitude, longitude: drawn.longitude),
                to: GeoPoint(latitude: person.point.latitude, longitude: person.point.longitude)
            )
            let observed = now.timeIntervalSince(track.startedAt)
            let duration = min(Self.maxDuration, max(Self.minDuration, observed))
            next[person.id] = gap > Self.teleportMeters
                ? Track(from: person.point, to: person.point, startedAt: now, duration: duration)
                : Track(from: drawn, to: person.point, startedAt: now, duration: duration)
        }
        tracks = next
    }

    func point(for id: String, at now: Date) -> VisualPoint? {
        tracks[id].map { Self.position(of: $0, at: now) }
    }

    func isSettled(at now: Date) -> Bool {
        tracks.values.allSatisfy { now.timeIntervalSince($0.startedAt) >= $0.duration }
    }

    private static func position(of track: Track, at now: Date) -> VisualPoint {
        let t = min(1, max(0, now.timeIntervalSince(track.startedAt) / track.duration))
        return VisualPoint(
            latitude: track.from.latitude + (track.to.latitude - track.from.latitude) * t,
            longitude: track.from.longitude + (track.to.longitude - track.from.longitude) * t
        )
    }
}
```

- [ ] **Step 4:** Run `PlayerGlideTests`. Expected: PASS.
- [ ] **Step 5: `HuntMap`.** Add `var glidePeople: Bool = false` and `@State private var glide = PlayerGlide()`. Move the current `Map { ... }` chain, with all its modifiers (`mapStyle`, `onMapCameraChange`, overlays, `onAppear`, `onChange(of: frameID)`), into `private func mapContent(now: Date) -> some View`. New body:

```swift
private var animates: Bool { glidePeople }   // Task 4 adds `|| zoneShrink != nil`

var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
        mapContent(now: timeline.date)
    }
    .onAppear { glide.retarget(people, now: Date()) }
    .onChange(of: people) { _, updated in glide.retarget(updated, now: Date()) }
}
```

Change `displayPoint(for:)` to `displayPoint(for person: VisualPlayer, now: Date)`. Its base point is `glidePeople ? (glide.point(for: person.id, at: now) ?? person.point) : person.point`. The fuzzy offset logic stays. The annotation uses `displayPoint(for: person, now: now)`. The editor passes nothing, so `paused` stays true and nothing redraws per frame.

- [ ] **Step 6:** In `LiveGameView` add `glidePeople: true` to the `HuntMap(` call. Run the full iOS suite.
- [ ] **Step 7: Performance check (manual).** Run `scripts/home-server.sh`, build to the booted iPhone 16 Pro, sign in, join `PARK42`, start the hunt and set 10x in Demo. Pins should glide and nothing should flicker or drop annotations. Profile with Instruments Time Profiler. If the map thread stays hot (about 25% CPU or more), drop `minimumInterval` to 1/20. If that is still janky, stop and report. The fallback is approach B from "Approaches considered", which needs its own plan.
- [ ] **Step 8: Commit** `PlayerGlide.swift`, `HuntMap.swift`, `LiveGameView.swift`, `PlayerGlideTests.swift` by explicit path. Message: `feat: glide player pins between snapshots`.

### Task 4: Zone shrink preview and contraction

**Files:**
- Create: `ios/Manhunt/Domain/ZoneShrinkPlan.swift`
- Modify: `ios/Manhunt/HuntMap.swift`, `ios/Manhunt/Store/AppStore.swift` (new computed property), `ios/Manhunt/LiveGameView.swift`
- Test: `ios/ManhuntTests/ZoneShrinkPlanTests.swift`

**Interfaces:**
- Consumes: `ClockLead.seconds(rate:anchoredAt:now:)` and `ClockLead.rate(snapshot:paused:)` (Task 2), `ZoneTimerDTO.intervalS` (Task 1), the `TimelineView` in `HuntMap` (Task 3).
- Produces: `ZoneShrinkPlan.visual(radiusM:nextRadiusM:shrinksInS:intervalS:) -> ZoneShrinkVisual`; `ZoneShrinkClock(zone:anchoredAt:rate:).visual(at:)`; `AppStore.zoneShrinkClock: ZoneShrinkClock?`; `HuntMap.zoneShrink: ZoneShrinkClock? = nil`.

- [ ] **Step 1: Extend `ZoneShrinkPlanTests`** (keep the Task 1 decode test):

```swift
private let t0 = Date(timeIntervalSince1970: 3_000)

/// Interval 60 s, ring 200 m shrinking to 150 m.
private func visual(shrinksIn: Double?, next: Double? = 150, interval: Double? = 60) -> ZoneShrinkVisual {
    ZoneShrinkPlan.visual(radiusM: 200, nextRadiusM: next, shrinksInS: shrinksIn, intervalS: interval)
}

func testNoPreviewBeforeTheHalfwayPoint() {
    let v = visual(shrinksIn: 40)
    XCTAssertNil(v.nextRadiusM)
    XCTAssertEqual(v.previewOpacity, 0)
    XCTAssertEqual(v.radiusM, 200)
}

func testDashedRingFadesInAfterHalfway() {
    XCTAssertEqual(visual(shrinksIn: 30).previewOpacity, 0, accuracy: 1e-9)
    let mid = visual(shrinksIn: 28.5)
    XCTAssertEqual(mid.previewOpacity, 0.5, accuracy: 1e-9)
    XCTAssertEqual(mid.nextRadiusM, 150)
    XCTAssertEqual(visual(shrinksIn: 20).previewOpacity, 1, accuracy: 1e-9)
    XCTAssertEqual(visual(shrinksIn: 20).radiusM, 200)
}

func testRingContractsDuringTheLastQuarterAndLandsOnTheNextRadius() {
    XCTAssertEqual(visual(shrinksIn: 15).radiusM, 200, accuracy: 1e-9)
    XCTAssertEqual(visual(shrinksIn: 7.5).radiusM, 175, accuracy: 1e-9)
    XCTAssertEqual(visual(shrinksIn: 0).radiusM, 150, accuracy: 1e-9)
    XCTAssertLessThan(visual(shrinksIn: 3).radiusM, visual(shrinksIn: 9).radiusM)
}

func testNothingToPreviewAtFinalSizeOrWithoutAnInterval() {
    XCTAssertEqual(visual(shrinksIn: nil, next: nil).previewOpacity, 0)
    XCTAssertEqual(visual(shrinksIn: 5, next: nil).radiusM, 200)
    let old = visual(shrinksIn: 5, interval: nil)
    XCTAssertEqual(old.radiusM, 200)
    XCTAssertNil(old.nextRadiusM)
    XCTAssertEqual(visual(shrinksIn: 5, interval: 0).radiusM, 200)
}

func testFirstIntervalThatIncludesHeadStartStaysQuiet() {
    let v = visual(shrinksIn: 120)
    XCTAssertNil(v.nextRadiusM)
    XCTAssertEqual(v.radiusM, 200)
}

func testClockExtrapolatesTheCountdownAndFreezesWhenPaused() {
    let zone = ZoneTimerDTO(radiusM: 200, nextRadiusM: 150, shrinksInS: 15, intervalS: 60)
    let running = ZoneShrinkClock(zone: zone, anchoredAt: t0, rate: 1)
    XCTAssertEqual(running.visual(at: t0).radiusM, 200, accuracy: 1e-9)
    XCTAssertLessThan(running.visual(at: t0.addingTimeInterval(0.8)).radiusM, 200)
    let paused = ZoneShrinkClock(zone: zone, anchoredAt: t0, rate: 0)
    XCTAssertEqual(paused.visual(at: t0.addingTimeInterval(0.8)).radiusM, 200, accuracy: 1e-9)
}
```

- [ ] **Step 2:** Run `-only-testing:ManhuntTests/ZoneShrinkPlanTests`. Expected: FAIL (build error).
- [ ] **Step 3: Implement `ZoneShrinkPlan.swift`:**

```swift
import Foundation

struct ZoneShrinkVisual: Equatable {
    /// Radius of the solid play-area ring to draw right now.
    var radiusM: Double
    /// Radius of the dashed next-zone ring. Nil when there is nothing to preview.
    var nextRadiusM: Double?
    var previewOpacity: Double
}

enum ZoneShrinkPlan {
    /// The dashed ring appears when this share of the interval is left.
    static let previewStart = 0.5
    /// The solid ring contracts over this final share of the interval and lands on the dashed ring.
    static let contractionShare = 0.25
    /// Dashed ring fade-in length, as a share of the interval.
    static let fadeShare = 0.05

    static func visual(
        radiusM: Double,
        nextRadiusM: Double?,
        shrinksInS: Double?,
        intervalS: Double?
    ) -> ZoneShrinkVisual {
        let plain = ZoneShrinkVisual(radiusM: radiusM, nextRadiusM: nil, previewOpacity: 0)
        // TODO: servers older than the interval_s field send no interval. Show no preview for them.
        guard let next = nextRadiusM, next < radiusM,
              let shrinksIn = shrinksInS,
              let interval = intervalS, interval > 0
        else { return plain }
        let left = shrinksIn / interval
        guard left <= previewStart else { return plain }
        let opacity = min(1, max(0, (previewStart - left) / fadeShare))
        let progress = min(1, max(0, (contractionShare - left) / contractionShare))
        let eased = progress * progress * (3 - 2 * progress)
        return ZoneShrinkVisual(
            radiusM: radiusM + (next - radiusM) * eased,
            nextRadiusM: next,
            previewOpacity: opacity
        )
    }
}

/// Zone timer plus the anchor it arrived on, so the map can animate between snapshots.
struct ZoneShrinkClock: Equatable {
    var zone: ZoneTimerDTO
    var anchoredAt: Date
    var rate: Double

    func visual(at now: Date) -> ZoneShrinkVisual {
        let lead = ClockLead.seconds(rate: rate, anchoredAt: anchoredAt, now: now)
        return ZoneShrinkPlan.visual(
            radiusM: zone.radiusM,
            nextRadiusM: zone.nextRadiusM,
            shrinksInS: zone.shrinksInS.map { max(0, Double($0) - lead) },
            intervalS: zone.intervalS.map(Double.init)
        )
    }
}
```

- [ ] **Step 4:** Run `ZoneShrinkPlanTests`. Expected: PASS.
- [ ] **Step 5: `AppStore`.**

```swift
var zoneShrinkClock: ZoneShrinkClock? {
    guard let match, let zone = match.snapshot.timers?.zone, match.snapshot.phase != .ended else { return nil }
    return ZoneShrinkClock(
        zone: zone,
        anchoredAt: match.clockAnchorAt,
        rate: ClockLead.rate(snapshot: match.snapshot, paused: paused)
    )
}
```

- [ ] **Step 6: `HuntMap`.** Add `var zoneShrink: ZoneShrinkClock? = nil` and change `animates` to `glidePeople || zoneShrink != nil`. In the `boundaryCircle` branch of `mapContent(now:)`:

```swift
if let circle = boundaryCircle {
    let shown = zoneShrink?.visual(at: now)
    let center = CLLocationCoordinate2D(latitude: circle.center.latitude, longitude: circle.center.longitude)
    MapCircle(center: center, radius: shown?.radiusM ?? circle.radiusMeters)
        .foregroundStyle(HuntColor.signal.opacity(0.18))
        .stroke(HuntColor.signal, lineWidth: 2)
    if let shown, let next = shown.nextRadiusM, shown.previewOpacity > 0 {
        MapCircle(center: center, radius: next)
            .foregroundStyle(.clear)
            .stroke(HuntColor.paper.opacity(0.9 * shown.previewOpacity),
                    style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
    }
}
```

In `LiveGameView` pass `zoneShrink: store.zoneShrinkClock`.

- [ ] **Step 7:** Run the full iOS suite. Manual check: in the demo (interval 60 s, `shrink_to` 75), set 10x. The dashed ring should appear about 3 s into each interval. The solid ring should contract over the last 1.5 s and land exactly on it. At 1x the contraction takes 15 s.
- [ ] **Step 8: Commit** `ZoneShrinkPlan.swift`, `HuntMap.swift`, `AppStore.swift`, `LiveGameView.swift`, `ZoneShrinkPlanTests.swift` by explicit path. Message: `feat: preview and animate the zone shrink`.

### Task 5: Ping flash

**Files:**
- Create: `ios/Manhunt/Domain/PingDetector.swift`, `ios/Manhunt/PingFlashOverlay.swift`
- Modify: `ios/Manhunt/Store/AppStore.swift` (`PingPulse`, `pingPulse`, `apply`), `ios/Manhunt/LiveGameView.swift`
- Test: `ios/ManhuntTests/PingDetectorTests.swift`

**Interfaces:**
- Consumes: `Fixtures.liveView` (Task 2).
- Produces: `PingDetector.didPing(previous: PlayerViewDTO?, next: PlayerViewDTO) -> Bool`; `struct PingPulse: Equatable { var id = UUID(); var role: PlayerRole }`; `AppStore.pingPulse: PingPulse?`; `PingFlashOverlay(pulse: PingPulse?)`.

- [ ] **Step 1: Write the failing tests:**

```swift
import XCTest
@testable import Manhunt

final class PingDetectorTests: XCTestCase {
    func testCountdownWrapIsAPing() {
        let before = Fixtures.liveView(elapsed: 59, nextReveal: 1)
        let after = Fixtures.liveView(elapsed: 60, nextReveal: 60)
        XCTAssertTrue(PingDetector.didPing(previous: before, next: after))
    }

    func testOrdinaryCountdownIsNotAPing() {
        let before = Fixtures.liveView(elapsed: 30, nextReveal: 30)
        let after = Fixtures.liveView(elapsed: 31, nextReveal: 29)
        XCTAssertFalse(PingDetector.didPing(previous: before, next: after))
    }

    func testTenTimesSpeedStillPingsWhenTheWrapHidesInsideOneSnapshot() {
        let before = Fixtures.liveView(elapsed: 56, nextReveal: 4)
        let after = Fixtures.liveView(elapsed: 66, nextReveal: 54)
        XCTAssertTrue(PingDetector.didPing(previous: before, next: after))
    }

    func testForcedRevealPingsOnTheTickThatFiresNotOnTheReply() {
        let before = Fixtures.liveView(elapsed: 20, nextReveal: 40)
        let reply = Fixtures.liveView(elapsed: 20, nextReveal: 0)
        XCTAssertFalse(PingDetector.didPing(previous: before, next: reply))
        let fired = Fixtures.liveView(elapsed: 21, nextReveal: 60)
        XCTAssertTrue(PingDetector.didPing(previous: reply, next: fired))
    }

    func testNoPingWithoutAHistoryATimerOrALiveClock() {
        let view = Fixtures.liveView(elapsed: 60, nextReveal: 60)
        XCTAssertFalse(PingDetector.didPing(previous: nil, next: view))
        let noTimer = Fixtures.liveView(elapsed: 61, nextReveal: nil)
        XCTAssertFalse(PingDetector.didPing(previous: view, next: noTimer))
        let paused = Fixtures.liveView(phase: .paused, elapsed: 60, nextReveal: 60)
        XCTAssertFalse(PingDetector.didPing(previous: Fixtures.liveView(elapsed: 60, nextReveal: 1), next: paused))
        let lobby = Fixtures.liveView(phase: .lobby, elapsed: 0, nextReveal: 60)
        XCTAssertFalse(PingDetector.didPing(previous: lobby, next: lobby))
    }

    @MainActor
    func testApplyRaisesAPulseForTheViewersRole() {
        let store = AppStore.makePreview()
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .hider))
        XCTAssertNil(store.pingPulse)
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .hider))
        XCTAssertEqual(store.pingPulse?.role, .hider)
    }
}
```

- [ ] **Step 2:** Run `-only-testing:ManhuntTests/PingDetectorTests`. Expected: FAIL (build error).
- [ ] **Step 3: Implement `PingDetector`:**

```swift
import Foundation

/// A ping fires when the reveal countdown reaches zero. The server never shows a natural 0, it
/// resets to the interval on the same tick, so "countdown <= elapsed game seconds and it is now
/// above zero" means a pulse happened in between. The server `reveal` event is not used: it is
/// only sent when pins were added, which misses hot/cold pulses.
enum PingDetector {
    static func didPing(previous: PlayerViewDTO?, next: PlayerViewDTO) -> Bool {
        guard let previous,
              let before = previous.timers?.nextRevealInS,
              let after = next.timers?.nextRevealInS,
              next.phase == .headStart || next.phase == .active
        else { return false }
        let elapsed = next.gameElapsedS - previous.gameElapsedS
        return elapsed > 0 && before <= elapsed && after > 0
    }
}
```

- [ ] **Step 4:** In `AppStore` add `struct PingPulse: Equatable { var id = UUID(); var role: PlayerRole }` and `var pingPulse: PingPulse?`. At the top of `apply(_:now:)`, before `match` is replaced: `if PingDetector.didPing(previous: match?.snapshot, next: view) { pingPulse = PingPulse(role: view.you.role) }`. Reset `pingPulse = nil` where the match is cleared (`leaveMatchThenHome`, `signOut`, and the `.ended` branch). Run `PingDetectorTests`. Expected: PASS.
- [ ] **Step 5: Implement `PingFlashOverlay`.** Single flash of about 1 s with at most one pulse per reveal interval (minimum 20 s), so it is nowhere near the photosensitivity limit of 3 flashes per second. Reduce Motion drops the expanding ring.

```swift
import SwiftUI

struct PingFlashOverlay: View {
    var pulse: PingPulse?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Frame {
        var glow = 0.0
        var ring = 0.2
        var ringOpacity = 0.0
        var label = 0.0
    }

    var body: some View {
        let isHider = pulse?.role == .hider
        let tint = isHider ? HuntColor.danger : HuntColor.signal
        KeyframeAnimator(initialValue: Frame(), trigger: pulse?.id) { frame in
            ZStack {
                Rectangle()
                    .strokeBorder(tint, lineWidth: 30)
                    .blur(radius: 16)
                    .opacity(frame.glow)
                if !reduceMotion {
                    Circle()
                        .stroke(tint, lineWidth: 6)
                        .scaleEffect(frame.ring)
                        .opacity(frame.ringOpacity)
                }
                Text(isHider ? "PINGED" : "PING")
                    .font(HuntFont.title(40))
                    .tracking(4)
                    .foregroundStyle(HuntColor.paper)
                    .shadow(color: .black.opacity(0.7), radius: 8)
                    .opacity(frame.label)
            }
            .ignoresSafeArea()
        } keyframes: { _ in
            KeyframeTrack(\.glow) {
                LinearKeyframe(0.95, duration: 0.12)
                CubicKeyframe(0, duration: 0.85)
            }
            KeyframeTrack(\.ring) { CubicKeyframe(2.6, duration: 1.0) }
            KeyframeTrack(\.ringOpacity) {
                LinearKeyframe(0.85, duration: 0.1)
                CubicKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.label) {
                LinearKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 0.45)
                CubicKeyframe(0, duration: 0.4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(trigger: pulse?.id) { _, new in
            guard new != nil else { return nil }
            return isHider ? .warning : .impact(weight: .medium)
        }
    }
}
```

- [ ] **Step 6:** In `LiveGameView`'s top-level `ZStack`, after the main `VStack`, add `PingFlashOverlay(pulse: store.pingPulse)`. Run the full iOS suite.
- [ ] **Step 7: Manual check.** In the demo as a seeker or hider, open Demo and tap "Force reveal" (it fires on the next tick). Close the sheet quickly, or wait for the natural 60 s ping. Expect a brief edge glow, an expanding ring and a "PING" or "PINGED" label. Also run once with Settings > Accessibility > Motion > Reduce Motion on. Expect only the glow and label.
- [ ] **Step 8: Commit** `PingDetector.swift`, `PingFlashOverlay.swift`, `AppStore.swift`, `LiveGameView.swift`, `PingDetectorTests.swift` by explicit path. Message: `feat: flash the screen when a ping fires`.

### Task 6: Button press animation and haptics

**Files:**
- Create: `ios/Manhunt/ButtonFeedback.swift`
- Modify: `Components.swift`, `LiveGameView.swift`, `LiveControls.swift`, `LobbyView.swift`, `HomeView.swift`, `CreateGameView.swift`, `ArenaEditorView.swift`, `DemoPanelView.swift`, `SignInView.swift`, `HuntMap.swift`
- Test: none for the views. Haptics cannot be asserted in unit tests or heard in the simulator. The verification is the `rg` check and a device pass.

**Interfaces:**
- Produces: `HuntHaptic` (`.light`, `.medium`, `.selection`, `.warning`), `HuntPressStyle`, `ButtonStyle.huntPress` and `ButtonStyle.huntPress(_:)`, `HuntButton(..., haptic: HuntHaptic = .medium, action:)`.

- [ ] **Step 1: Create `ButtonFeedback.swift`.** The environment values live in an inner view because that is the known-good way to read them from a `ButtonStyle`.

```swift
import SwiftUI

/// How a tap should feel. Light for chrome, medium for the action the screen is about.
enum HuntHaptic {
    case light, medium, selection, warning

    var feedback: SensoryFeedback {
        switch self {
        case .light: .impact(flexibility: .soft, intensity: 0.6)
        case .medium: .impact(weight: .medium)
        case .selection: .selection
        case .warning: .warning
        }
    }
}

/// Shared press feel: spring scale, slight dim, haptic on touch-down. A disabled button stays
/// silent. Reduce Motion keeps the dim and drops the scale.
struct HuntPressStyle: ButtonStyle {
    var haptic: HuntHaptic

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, haptic: haptic)
    }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        let haptic: HuntHaptic
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
                .sensoryFeedback(haptic.feedback, trigger: configuration.isPressed) { _, pressed in
                    pressed && isEnabled
                }
        }
    }
}

extension ButtonStyle where Self == HuntPressStyle {
    static var huntPress: HuntPressStyle { HuntPressStyle(haptic: .light) }
    static func huntPress(_ haptic: HuntHaptic) -> HuntPressStyle { HuntPressStyle(haptic: haptic) }
}
```

- [ ] **Step 2: `HuntButton`.** Add `var haptic: HuntHaptic = .medium` between `ink` and `action`. Use `.buttonStyle(.huntPress(haptic))`. Existing call sites keep compiling. Pass `haptic: .light` for secondary actions ("Hold", "Resume", "Randomize roles", "Scan invite QR", "Home" on results). In `ScreenHeader` the back chevron uses `.huntPress`.
- [ ] **Step 3: Replace every remaining `.buttonStyle(.plain)` in `ios/Manhunt`** (about 35 sites) by role:
  - `.huntPress(.medium)`: live dock Taunt, Scan/Tag, UWB tag buttons, power-up chips, flashlight, Drop point, Sign in, arena-card "open" rows in `CreateGameView`.
  - `.huntPress(.light)`: map chips (Home, Leaderboard, Event log, Demo, Walk), host-controls icon, Show tag code, speaker and mic, My location, role-cycle rows and "New arena" and preset rows in Home/Lobby/Create, Arena editor back and layers buttons, Demo `actionPill` and bot circle buttons, banner "Open Settings".
  - `.huntPress(.selection)`: segmented pill groups: My team, Head start lock, Demo speed 1x/2x/5x/10x, Create-game option pills.
  - `.huntPress(.warning)`: Lobby "Remove player".
  - Leave alone (system-owned, already animate and buzz): buttons inside `contextMenu`, `confirmationDialog`, `alert`, `.toolbar` "Done", `SignInWithAppleButton`, `Toggle`, `Stepper`, `Picker`, and plain text buttons inside `List` rows such as "Rename" and "Delete".
- [ ] **Step 4: Verify the sweep.** `rg -n "buttonStyle\(\.plain\)" ios/Manhunt` should return nothing. Build and run the full iOS suite. Expected: PASS, and the `accessibilityIdentifier`s on `taunt`, `tag`, `demo-*` and `start-hunt` still resolve.
- [ ] **Step 5: Commit** the new file and the modified view files by explicit path. Message: `feat: add press animation and haptics to buttons`.

### Task 7: State-change animations

**Files:** Modify `LiveGameView.swift`, `LiveControls.swift`, `LobbyView.swift`, `DemoPanelView.swift`. No tests, because these are presentation-only. Verify by eye.

- [ ] **Step 1:** Dock and controls swap while picking a decoy or a demo walk target. Give the dock and `LiveControls` `.transition(.move(edge: .bottom).combined(with: .opacity))`. Add `.animation(.snappy, value: store.decoyPicking || store.demoPicking)` on the container. Give the picker bar a matching top transition.
- [ ] **Step 2:** Banners and the reconnecting and out-of-bounds cards get `.transition(.move(edge: .top).combined(with: .opacity))`. Animate the top column with `.animation(.snappy, value: store.situation)`.
- [ ] **Step 3:** Flashlight icon uses `.contentTransition(.symbolEffect(.replace))`. Its background, ring and glow animate with `.animation(.snappy, value: flashlightOn)`.
- [ ] **Step 4:** Power-up chips animate enabled/disabled with `.animation(.easeOut(duration: 0.2), value: enabled)`. The dock points readout (`"\(store.shownPoints) pts"`) gets `.contentTransition(.numericText())` and `.animation(.snappy, value: store.shownPoints)`. The Taunt label gets `.contentTransition(.numericText(countsDown: true))`.
- [ ] **Step 5:** Segmented pills in Lobby and Demo panel animate selection with `.animation(.snappy, value: selected)`.
- [ ] **Step 6:** Run the full iOS suite. Commit by explicit path with the message `feat: animate live screen state changes`.

### Task 8: Verification

- [ ] **Step 1:** `cd server && . .venv/bin/activate && pytest -q && ruff check .`. Expected: all pass, ruff clean. Record the pass counts.
- [ ] **Step 2:** `xcodebuild test -project ios/Manhunt.xcodeproj -scheme Manhunt -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4'`. Expected: all pass, including the four new test classes. Record the counts.
- [ ] **Step 3: Simulator walkthrough (record findings, not assumptions).** Run `scripts/home-server.sh`, join `PARK42` as host and start the hunt.
  - At 1x and 10x the clock digits roll and the bar glides with no steps.
  - Bots and your own dot glide, and "Move me" walks smoothly.
  - The dashed ring appears halfway through an interval, and the yellow ring contracts over the last quarter onto it.
  - "Force reveal" produces the flash. Pause freezes the clock, bar and ring.
- [ ] **Step 3b: Device pass (human gate).** Haptics only exist on a phone. Scott feels the press haptics, the ping haptic for both roles, and confirms nothing buzzes on disabled chips. Leave this open until a person does it. Do not report it as verified.
- [ ] **Step 4:** Do not touch `remaining-benchmarks.md`. Update the spec's status line to "implemented, device haptics pending".
- [ ] **Step 5:** Push the branch. Do not open a PR unless Scott asks. In the final message, say that AGENTS.md and his hard rules conflict with the cloud harness default of opening a PR. List anything not run (Instruments on a device, haptics).

## Risks and open items

- **Per-frame `Map` content (Task 3).** The one real unknown. It is mitigated by running only on the live map, a 30 Hz cap, and a defined fallback.
- **Display lag.** Pins run about one snapshot (up to about 1.25 s) behind the server by design. Extrapolating instead would overshoot when a bot turns.
- **Contraction timing (Assumption 4).** If you want "after the shrink", the live ring would be larger than the real boundary for a quarter interval. I would push back on that for safety reasons, but it is a one-function change.
- **Reconnect after a long gap.** `PingDetector` can flash late for a ping that really happened during the gap. That is correct but late.
- **Old servers.** No `interval_s` means no dashed ring or contraction. The ring still draws at the snapshot radius.

## Self-review

- **Coverage:** smooth bar, timer and pins are Tasks 2 and 3. The ping flash is Task 5. The dashed next-zone ring at halfway and the quarter-time contraction are Tasks 1 and 4. Button animations and haptics are Tasks 6 and 7.
- **Placeholders:** none. Every code step has code. Task 6 and Task 7 describe edits by call site because they are mechanical swaps over about 35 sites.
- **Type consistency:** `ClockLead.rate/seconds/anchor`, `PhaseClock(leadS:)`, `MatchHandle.clockAnchorAt`, `ZoneTimerDTO.intervalS`, `ZoneShrinkClock(zone:anchoredAt:rate:)`, `PlayerGlide.retarget/point/isSettled`, `PingDetector.didPing`, `PingPulse` and `HuntHaptic` are used under the same names in every task.
