import XCTest
@testable import Manhunt

@MainActor
final class PreviewMatchTests: XCTestCase {
    func testHeadStartHonorsTheEditedDurationThenUnlocksSeekers() {
        var preset = RulePreset.classic()
        preset.setDuration(module: "head_start", field: "duration", seconds: 12)
        let match = makeMatch(preset: preset)
        let hider = match.recruit(name: "Riley", role: .hider, isYou: true, isHost: true)
        _ = match.recruit(name: "Jordan", role: .seeker, isYou: false, isHost: false)
        XCTAssertNil(match.start())
        XCTAssertEqual(match.snapshot.phase, .headStart)
        XCTAssertFalse(match.snapshot.hidesMap)
        match.advance(seconds: 11)
        XCTAssertEqual(match.snapshot.phase, .headStart)
        match.advance(seconds: 1)
        XCTAssertEqual(match.snapshot.phase, .active)
        XCTAssertNotNil(hider)
    }

    func testDisabledHeadStartStartsActiveAndCannotStartWithoutBothRoles() {
        var preset = RulePreset.classic()
        preset.setEnabled("head_start", enabled: false)
        let match = makeMatch(preset: preset)
        _ = match.recruit(name: "Riley", role: .unassigned, isYou: true, isHost: true)
        _ = match.recruit(name: "Jordan", role: .unassigned, isYou: false, isHost: false)
        XCTAssertEqual(match.start(), .needBothRoles)

        match.randomizeRoles(hiderCount: 1, seed: 4)
        XCTAssertNil(match.start())
        XCTAssertEqual(match.snapshot.phase, .active)
    }

    func testTagRequiresBothRangesAndAGpsPairThenUndoRestoresTheHider() {
        let match = startedHunt()
        let seeker = match.snapshot.players.first { $0.role == .seeker }!
        let hider = match.snapshot.players.first { $0.role == .hider }!
        match.refreshLocation(player: seeker.id, coordinate: Fixtures.meters(x: 100, y: 100), accuracy: 5)
        match.refreshLocation(player: hider.id, coordinate: Fixtures.meters(x: 100, y: 110), accuracy: 5)

        XCTAssertEqual(
            match.claimTag(seeker: seeker.id, hider: hider.id, seekerRange: 10, hiderRange: 10),
            .rejected(.tooFar)
        )

        match.refreshLocation(player: hider.id, coordinate: Fixtures.meters(x: 100, y: 101), accuracy: 5)
        XCTAssertEqual(
            match.claimTag(seeker: seeker.id, hider: hider.id, seekerRange: 1, hiderRange: 9),
            .rejected(.tooFar)
        )
        XCTAssertEqual(
            match.claimTag(seeker: seeker.id, hider: hider.id, seekerRange: 1, hiderRange: 1),
            .accepted
        )
        XCTAssertEqual(match.snapshot.players.first { $0.id == hider.id }?.status, .eliminated)
        XCTAssertEqual(match.snapshot.players.first { $0.id == seeker.id }?.points, 125)

        XCTAssertTrue(match.undoLastTag())
        XCTAssertEqual(match.snapshot.players.first { $0.id == hider.id }?.status, .active)
        XCTAssertEqual(match.snapshot.players.first { $0.id == seeker.id }?.points, 100)
    }

    func testAFarGpsPairCannotBeSavedByAFakeUwbReading() {
        let match = startedHunt()
        let seeker = match.snapshot.players.first { $0.role == .seeker }!
        let hider = match.snapshot.players.first { $0.role == .hider }!
        match.refreshLocation(player: seeker.id, coordinate: Fixtures.meters(x: 40, y: 40), accuracy: 5)
        match.refreshLocation(player: hider.id, coordinate: Fixtures.meters(x: 160, y: 160), accuracy: 5)
        XCTAssertEqual(
            match.claimTag(seeker: seeker.id, hider: hider.id, seekerRange: 1, hiderRange: 1),
            .rejected(.notInPairingRange)
        )
    }

    func testShieldAndSafeZonesBlockTagsUntilLockdown() {
        let match = startedHunt()
        let seeker = match.snapshot.players.first { $0.role == .seeker }!
        let hider = match.snapshot.players.first { $0.role == .hider }!
        moveTogether(match, seeker: seeker.id, hider: hider.id)

        XCTAssertEqual(match.purchase(hider, kind: .shield, target: nil), .accepted)
        XCTAssertEqual(
            match.claimTag(seeker: seeker.id, hider: hider.id, seekerRange: 1, hiderRange: 1),
            .rejected(.shielded)
        )

        match.advance(seconds: PowerUpKind.shield.durationSeconds + 1)
        var arena = Fixtures.square()
        arena.zones = [
            ArenaZone(
                id: UUID(),
                name: "Gazebo",
                kind: .safe,
                shape: .circle(center: Fixtures.meters(x: 100, y: 101), radiusMeters: 15)
            ),
        ]
        let sheltered = PreviewMatch(
            arena: arena,
            preset: shortPreset(),
            now: Date(timeIntervalSince1970: 1_700_000_000),
            joinCode: "PARK42",
            seed: 2
        )
        let shelterHider = sheltered.recruit(name: "Riley", role: .hider, isYou: false, isHost: false)
        let shelterSeeker = sheltered.recruit(name: "Jordan", role: .seeker, isYou: true, isHost: true)
        XCTAssertNil(sheltered.start())
        sheltered.advance(seconds: 1)
        moveTogether(sheltered, seeker: shelterSeeker, hider: shelterHider)
        XCTAssertEqual(
            sheltered.claimTag(seeker: shelterSeeker, hider: shelterHider, seekerRange: 1, hiderRange: 1),
            .rejected(.safeZone)
        )
        XCTAssertEqual(sheltered.purchase(shelterSeeker, kind: .lockdown, target: nil), .accepted)
        XCTAssertEqual(
            sheltered.claimTag(seeker: shelterSeeker, hider: shelterHider, seekerRange: 1, hiderRange: 1),
            .accepted
        )
    }

    func testGhostHidesTheNextRevealAndADecoyMovesThePin() {
        var preset = shortPreset()
        preset.setNumber(module: "reveal_fuzzy", field: "interval", value: 2)
        preset.setNumber(module: "reveal_fuzzy", field: "fuzz", value: 0)
        let match = PreviewMatch(
            arena: Fixtures.square(),
            preset: preset,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            joinCode: "PARK42",
            seed: 3
        )
        let hidden = match.recruit(name: "Riley", role: .hider, isYou: true, isHost: true)
        let visible = match.recruit(name: "Quinn", role: .hider, isYou: false, isHost: false)
        _ = match.recruit(name: "Jordan", role: .seeker, isYou: false, isHost: false)
        XCTAssertNil(match.start())
        XCTAssertEqual(match.purchase(hidden, kind: .ghost, target: nil), .accepted)
        let decoyAt = Fixtures.meters(x: 30, y: 30)
        XCTAssertEqual(match.purchase(visible, kind: .decoy, target: decoyAt), .accepted)
        match.advance(seconds: 2)
        let pins = match.snapshot.reveals
        XCTAssertFalse(pins.contains { $0.playerID == hidden })
        let decoy = try? XCTUnwrap(pins.first { $0.playerID == visible })
        XCTAssertEqual(decoy?.isDecoy, true)
        XCTAssertEqual(decoy?.coordinate.latitude ?? -1, decoyAt.latitude, accuracy: 0.000_000_1)
    }

    func testDecoyOutsideThePlayAreaIsRejected() {
        let match = startedHunt()
        let hider = match.snapshot.players.first { $0.role == .hider }!
        XCTAssertEqual(
            match.purchase(hider.id, kind: .decoy, target: nil),
            .denied(.needsTarget)
        )
        XCTAssertEqual(
            match.purchase(hider.id, kind: .decoy, target: Fixtures.meters(x: 900, y: 900)),
            .denied(.targetOutside)
        )
    }

    func testScanRadarAndJammerChangeWhatEachRoleCanSee() {
        let match = startedHunt()
        let seeker = match.snapshot.players.first { $0.role == .seeker && $0.isYou }!
        let hider = match.snapshot.players.first { $0.role == .hider }!
        XCTAssertEqual(match.purchase(seeker.id, kind: .scan, target: nil), .accepted)
        XCTAssertEqual(match.snapshot.reveals.count, 1)
        XCTAssertTrue(match.snapshot.hotCold != nil)

        XCTAssertEqual(match.purchase(hider.id, kind: .jammer, target: nil), .accepted)
        XCTAssertNil(match.snapshot.hotCold)

        XCTAssertEqual(match.purchase(hider.id, kind: .radar, target: nil), .accepted)
        let hiderView = match.snapshot
        XCTAssertTrue(hiderView.players.contains { $0.role == .hider && $0.id == hider.id })
        // Radar is for the hider. Rebuild a you-hider match to read opponent pins.
        let hidersMatch = startedHunt(youAreHider: true)
        let you = hidersMatch.snapshot.players.first { $0.isYou }!
        XCTAssertTrue(hidersMatch.snapshot.opponentPins.isEmpty)
        XCTAssertEqual(hidersMatch.purchase(you.id, kind: .radar, target: nil), .accepted)
        XCTAssertFalse(hidersMatch.snapshot.opponentPins.isEmpty)
        XCTAssertTrue(hidersMatch.snapshot.opponentPins.allSatisfy { $0.role == .seeker })
    }

    func testOutOfBoundsCountdownEliminatesAHiderWhoStaysOutside() {
        var preset = shortPreset()
        preset.setDuration(module: "zone_policy", field: "oob_countdown", seconds: 3)
        let match = makeMatch(preset: preset)
        let hider = match.recruit(name: "Riley", role: .hider, isYou: true, isHost: true)
        _ = match.recruit(name: "Jordan", role: .seeker, isYou: false, isHost: false)
        XCTAssertNil(match.start())
        match.advance(seconds: 1)
        match.refreshLocation(player: hider, coordinate: Fixtures.meters(x: 100, y: -80), accuracy: 5)
        match.advance(seconds: 1)
        XCTAssertEqual(match.snapshot.players.first { $0.id == hider }?.bounds, .warning)
        match.advance(seconds: 1)
        XCTAssertEqual(match.snapshot.players.first { $0.id == hider }?.bounds, .countdown(remainingSeconds: 3))
        match.advance(seconds: 3)
        XCTAssertEqual(match.snapshot.players.first { $0.id == hider }?.status, .eliminated)
        XCTAssertTrue(match.snapshot.events.contains { $0.text.localizedCaseInsensitiveContains("out of bounds") })
    }

    func testSilenceShowsTheLastPreciseLocationToEveryone() {
        var preset = shortPreset()
        preset.setDuration(module: "signal_loss", field: "silence", seconds: 3)
        let match = makeMatch(preset: preset)
        let hider = match.recruit(name: "Riley", role: .hider, isYou: false, isHost: false)
        _ = match.recruit(name: "Jordan", role: .seeker, isYou: true, isHost: true)
        XCTAssertNil(match.start())
        match.advance(seconds: 1)
        let last = Fixtures.meters(x: 40, y: 40)
        match.refreshLocation(player: hider, coordinate: last, accuracy: 6)
        match.advance(seconds: 3)
        let player = match.snapshot.players.first { $0.id == hider }
        XCTAssertEqual(player?.status, .signalLost)
        XCTAssertEqual(player?.coordinate.latitude ?? 0, last.latitude, accuracy: 0.000_000_1)
        XCTAssertTrue(match.snapshot.banners.contains { $0.tone == .safety })
        XCTAssertTrue(match.snapshot.opponentPins.contains { $0.id == hider })
    }

    func testPauseFreezesTheHeadStartClock() {
        var preset = shortPreset()
        preset.setDuration(module: "head_start", field: "duration", seconds: 5)
        let match = makeMatch(preset: preset)
        _ = match.recruit(name: "Riley", role: .hider, isYou: true, isHost: true)
        _ = match.recruit(name: "Jordan", role: .seeker, isYou: false, isHost: false)
        XCTAssertNil(match.start())
        match.pause()
        match.advance(seconds: 20)
        XCTAssertEqual(match.snapshot.phase, .paused)
        match.resume()
        XCTAssertEqual(match.snapshot.phase, .headStart)
        match.advance(seconds: 5)
        XCTAssertEqual(match.snapshot.phase, .active)
    }

    func testCloseTauntScoresMoreThanADistantOne() {
        let close = startedHunt(youAreHider: true)
        let you = close.snapshot.players.first { $0.isYou }!
        let seeker = close.snapshot.players.first { $0.role == .seeker }!
        close.refreshLocation(player: you.id, coordinate: Fixtures.meters(x: 100, y: 100), accuracy: 5)
        close.refreshLocation(player: seeker.id, coordinate: Fixtures.meters(x: 100, y: 112), accuracy: 5)
        let closePoints = close.taunt(player: you.id)

        let far = startedHunt(youAreHider: true)
        let farYou = far.snapshot.players.first { $0.isYou }!
        let farSeeker = far.snapshot.players.first { $0.role == .seeker }!
        far.refreshLocation(player: farYou.id, coordinate: Fixtures.meters(x: 20, y: 20), accuracy: 5)
        far.refreshLocation(player: farSeeker.id, coordinate: Fixtures.meters(x: 180, y: 180), accuracy: 5)
        let farPoints = far.taunt(player: farYou.id)
        XCTAssertGreaterThan(closePoints, farPoints)
        XCTAssertGreaterThan(farPoints, 0)
    }

    func testSecondShieldPurchaseIsOnCooldown() {
        let match = startedHunt(youAreHider: true)
        let you = match.snapshot.players.first { $0.isYou }!
        XCTAssertEqual(match.purchase(you.id, kind: .shield, target: nil), .accepted)
        XCTAssertEqual(match.purchase(you.id, kind: .shield, target: nil), .denied(.coolingDown))
    }

    private func shortPreset() -> RulePreset {
        var preset = RulePreset.classic()
        preset.setDuration(module: "head_start", field: "duration", seconds: 1)
        preset.setDuration(module: "signal_loss", field: "silence", seconds: 60)
        preset.setNumber(module: "reveal_fuzzy", field: "interval", value: 30)
        return preset
    }

    private func makeMatch(preset: RulePreset) -> PreviewMatch {
        PreviewMatch(
            arena: Fixtures.square(),
            preset: preset,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            joinCode: "PARK42",
            seed: 1
        )
    }

    private func startedHunt(youAreHider: Bool = false) -> PreviewMatch {
        let match = makeMatch(preset: shortPreset())
        _ = match.recruit(name: "Riley", role: youAreHider ? .hider : .seeker, isYou: true, isHost: true)
        _ = match.recruit(name: "Jordan", role: youAreHider ? .seeker : .hider, isYou: false, isHost: false)
        XCTAssertNil(match.start())
        match.advance(seconds: 1)
        return match
    }

    private func moveTogether(_ match: PreviewMatch, seeker: UUID, hider: UUID) {
        match.refreshLocation(player: seeker, coordinate: Fixtures.meters(x: 100, y: 100), accuracy: 4)
        match.refreshLocation(player: hider, coordinate: Fixtures.meters(x: 100, y: 101), accuracy: 4)
    }
}
