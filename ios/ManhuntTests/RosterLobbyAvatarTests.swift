import XCTest
@testable import Manhunt

// MARK: - Fix freshness

final class FixFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func location(secondsAgo: Double, kind: String = "exact") -> LocationDTO {
        LocationDTO(
            lat: 40.66,
            lon: -73.96,
            accuracyM: 5,
            at: ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo)),
            kind: kind
        )
    }

    private func reading(
        _ location: LocationDTO?,
        status: PlayerStatus = .active,
        expectsFix: Bool = true,
        interval: Int = 60
    ) -> FixFreshness.Reading? {
        FixFreshness.reading(
            location: location,
            status: status,
            expectsFix: expectsFix,
            pingIntervalS: interval,
            now: now
        )
    }

    func testFourBarsUpToAndIncludingExactlyOneInterval() {
        XCTAssertEqual(reading(location(secondsAgo: 0))?.bars, 4)
        XCTAssertEqual(reading(location(secondsAgo: 60))?.bars, 4)
    }

    func testThreeBarsJustPastOneIntervalAndAtExactlyTwo() {
        XCTAssertEqual(reading(location(secondsAgo: 61))?.bars, 3)
        XCTAssertEqual(reading(location(secondsAgo: 120))?.bars, 3)
    }

    func testTwoBarsWhenOlderThanTwoIntervals() {
        let result = reading(location(secondsAgo: 121))
        XCTAssertEqual(result?.bars, 2)
        XCTAssertTrue(result?.label.hasPrefix("Stale") == true)
    }

    func testOneBarForSignalLostOrLastKnownHoweverRecent() {
        XCTAssertEqual(reading(location(secondsAgo: 5), status: .signalLost)?.bars, 1)
        XCTAssertEqual(reading(location(secondsAgo: 5, kind: "last_known"))?.bars, 1)
    }

    func testZeroBarsWhenAFixIsExpectedButMissing() {
        let result = reading(nil)
        XCTAssertEqual(result?.bars, 0)
        XCTAssertEqual(result?.label, "No fix yet")
    }

    func testNothingDrawnWhenTheViewerMayNotSeeThePlayer() {
        XCTAssertNil(reading(nil, expectsFix: false))
    }

    func testLabelReadsAsFreshnessNotSignalStrength() {
        XCTAssertEqual(reading(location(secondsAgo: 40))?.label, "Last fix 40 seconds ago")
        XCTAssertEqual(reading(location(secondsAgo: 1))?.label, "Last fix 1 second ago")
        XCTAssertTrue(reading(location(secondsAgo: 150))?.label.contains("2 minutes") == true)
    }

    func testFutureTimestampsClampToJustNow() {
        let result = reading(location(secondsAgo: -30))
        XCTAssertEqual(result?.bars, 4)
        XCTAssertEqual(result?.ageSeconds, 0)
    }

    func testUnparseableTimestampIsNoFixInsteadOfACrash() {
        let broken = LocationDTO(lat: 0, lon: 0, accuracyM: 1, at: "not a date", kind: "exact")
        XCTAssertEqual(reading(broken)?.bars, 0)
    }

    func testParsesPythonIsoformatWithMicrosecondsAndOffset() {
        XCTAssertNotNil(FixFreshness.parse("2026-11-24T20:00:00.123456+00:00"))
        XCTAssertNotNil(FixFreshness.parse("2026-11-24T20:00:00+00:00"))
    }

    func testThresholdsScaleWithTheMatchInterval() {
        XCTAssertEqual(reading(location(secondsAgo: 290), interval: 300)?.bars, 4)
        XCTAssertEqual(reading(location(secondsAgo: 601), interval: 300)?.bars, 2)
    }

    func testPingIntervalFallsBackThroughSeekerRevealToTheDefault() {
        XCTAssertEqual(
            FixFreshness.pingInterval(
                timers: TimersDTO(
                    headStartS: 60, timeLimitS: 1800, revealIntervalS: 90, nextRevealInS: nil,
                    zone: nil, seekerRevealIntervalS: 30
                )
            ),
            90
        )
        XCTAssertEqual(
            FixFreshness.pingInterval(
                timers: TimersDTO(
                    headStartS: 60, timeLimitS: 1800, revealIntervalS: nil, nextRevealInS: nil,
                    zone: nil, seekerRevealIntervalS: 30
                )
            ),
            30
        )
        XCTAssertEqual(FixFreshness.pingInterval(timers: nil), FixFreshness.defaultPingIntervalS)
    }

    func testViewerExpectsTeammatesAndSelfButNotTheOtherTeam() {
        let me = UUID()
        let them = UUID()
        func expects(_ role: PlayerRole, id: UUID = them, phase: MatchPhase = .active,
                     viewerStatus: PlayerStatus = .active) -> Bool {
            FixFreshness.viewerExpectsFix(
                viewerID: me, viewerRole: .hider, viewerStatus: viewerStatus,
                playerID: id, playerRole: role, phase: phase
            )
        }
        XCTAssertTrue(expects(.hider))
        XCTAssertTrue(expects(.seeker, id: me))
        XCTAssertFalse(expects(.seeker))
        XCTAssertFalse(expects(.hider, phase: .lobby))
        XCTAssertFalse(expects(.unassigned))
        XCTAssertFalse(expects(.hider, viewerStatus: .eliminated))
        XCTAssertTrue(expects(.hider, id: me, viewerStatus: .eliminated))
    }
}

// MARK: - Roster grouping

final class RosterGroupingTests: XCTestCase {
    private func player(
        _ name: String,
        _ role: PlayerRole,
        points: Int,
        converted: Bool = false,
        status: PlayerStatus = .active
    ) -> PlayerDTO {
        PlayerDTO(
            playerId: UUID(),
            displayName: name,
            role: role,
            status: status,
            isHost: false,
            points: points,
            convertedFromHider: converted
        )
    }

    func testSeekersAndHidersSectionsKeepOverallRankAndPoints() {
        let sections = RosterGrouping.group([
            player("a", .hider, points: 50),
            player("b", .seeker, points: 80),
            player("c", .hider, points: 20),
            player("d", .seeker, points: 10),
        ])
        XCTAssertEqual(sections.map(\.title), ["Seekers", "Hiders"])
        XCTAssertEqual(sections[0].rows.map { [$0.rank, $0.points] }, [[1, 80], [4, 10]])
        XCTAssertEqual(sections[1].rows.map { [$0.rank, $0.points] }, [[2, 50], [3, 20]])
    }

    func testConvertedPlayersSitUnderSeekersWithATaggedMarker() {
        let sections = RosterGrouping.group([
            player("a", .hider, points: 5),
            player("b", .seeker, points: 5, converted: true),
        ])
        XCTAssertEqual(sections.first { $0.id == .seekers }?.rows.first?.tagged, true)
        XCTAssertEqual(sections.first { $0.id == .hiders }?.rows.first?.tagged, false)
    }

    func testEliminatedHidersStayUnderHiders() {
        let sections = RosterGrouping.group([
            player("a", .hider, points: 5, status: .eliminated),
            player("b", .seeker, points: 5),
        ])
        XCTAssertEqual(sections.first { $0.id == .hiders }?.rows.count, 1)
    }

    func testUnassignedLobbyPlayersGetTheirOwnSectionAndEmptySectionsDrop() {
        let lobby = RosterGrouping.group([player("a", .unassigned, points: 0), player("b", .unassigned, points: 0)])
        XCTAssertEqual(lobby.map(\.id), [.unassigned])
        XCTAssertTrue(RosterGrouping.group([]).isEmpty)
    }

    func testTiesShareARankAndTheNextRankSkips() {
        let rows = RosterGrouping.rank([
            player("a", .hider, points: 10),
            player("b", .hider, points: 10),
            player("c", .hider, points: 5),
        ])
        XCTAssertEqual(rows.map(\.rank), [1, 1, 3])
    }

    func testTwentySevenPlayersAreAllKept() {
        let players = (0..<27).map { player("P\($0)", $0 % 3 == 0 ? .seeker : .hider, points: $0 % 5) }
        let total = RosterGrouping.group(players).reduce(0) { $0 + $1.rows.count }
        XCTAssertEqual(total, 27)
    }

    func testPointsEarnedWinsOverPoints() {
        let one = PlayerDTO(
            playerId: UUID(), displayName: "a", role: .hider, status: .active, isHost: false,
            points: 5, pointsEarned: 40
        )
        XCTAssertEqual(RosterGrouping.points(of: one), 40)
    }
}

// MARK: - Avatar style

final class AvatarStyleTests: XCTestCase {
    private func uuid(_ n: Int) -> String {
        "00000000-0000-4000-8000-" + String(format: "%012lx", n)
    }

    private func roster(_ pairs: [(String, String)]) -> [(id: String, name: String)] {
        pairs.map { (id: $0.0, name: $0.1) }
    }

    func testInitialsHandleEmptyOneLetterAccentedAndEmojiNames() {
        XCTAssertEqual(AvatarStyle.initials(from: "Ryan O\u{2019}Donnell"), "RO")
        XCTAssertEqual(AvatarStyle.initials(from: ""), "?")
        XCTAssertEqual(AvatarStyle.initials(from: "   "), "?")
        XCTAssertEqual(AvatarStyle.initials(from: "x"), "X")
        XCTAssertEqual(AvatarStyle.initials(from: "\u{00E9}lodie"), "\u{00C9}")
        XCTAssertEqual(AvatarStyle.initials(from: "Zo\u{00EB} \u{1F98A}"), "Z\u{1F98A}")
    }

    func testHashMatchesTheCrossPlatformFixtures() {
        // The same fixtures live in web/src/game/avatarStyle.test.ts.
        XCTAssertEqual(AvatarStyle.idHash(""), 5381)
        XCTAssertEqual(AvatarStyle.idHash("a"), 177_670)
        XCTAssertEqual(AvatarStyle.idHash(uuid(1)), 919_571_334)
        XCTAssertEqual(AvatarStyle.idHash(uuid(4)), 919_571_337)
    }

    func testFixtureRosterGetsTheSameSlotsAndCuesAsWeb() {
        let styles = AvatarStyle.assign(players: roster([
            (uuid(1), "Sam Smith"), (uuid(2), "Sara Stone"), (uuid(3), "Sid Shaw"), (uuid(4), "Zed Zimmer"),
        ]))
        XCTAssertEqual((1...4).map { styles[uuid($0)]?.colorIndex }, [6, 7, 8, 9])
        XCTAssertEqual((1...4).map { styles[uuid($0)]?.cue }, [0, 1, 2, 0])
    }

    func testSameInitialsNeverShareAColorWhileColorsRemain() {
        let count = AvatarStyle.paletteRGB.count
        let players = roster((0..<count).map { (uuid($0 + 1), "Sam Smith \($0)") })
        let styles = AvatarStyle.assign(players: players)
        XCTAssertEqual(Set(players.map { styles[$0.id]?.colorIndex }).count, count)
    }

    func testResultDoesNotDependOnRosterOrderOrIdCase() {
        let players = roster((0..<12).map { (uuid($0 + 1), "Pat Poe") })
        let forward = AvatarStyle.assign(players: players)
        let backward = AvatarStyle.assign(players: Array(players.reversed()))
        for player in players {
            XCTAssertEqual(forward[player.id], backward[player.id])
        }
        let upper = AvatarStyle.assign(players: roster([(uuid(10).uppercased(), "Al Bo")]))
        let lower = AvatarStyle.assign(players: roster([(uuid(10), "Al Bo")]))
        XCTAssertEqual(upper.values.first, lower.values.first)
    }

    func testDuplicateColorsOnlyWhenSameInitialPlayersOutnumberTheColors() {
        let count = AvatarStyle.paletteRGB.count
        let players = roster((0..<(count + 3)).map { (uuid($0 + 1), "Kim Kane") })
        let styles = AvatarStyle.assign(players: players)
        XCTAssertEqual(Set(styles.values.map(\.colorIndex)).count, count)
        XCTAssertEqual(Set(styles.values.map(\.cue)).count, 4)
        XCTAssertEqual(styles[uuid(13)]?.cue, 0)
        XCTAssertEqual(styles[uuid(14)]?.cue, 1)
    }

    func testEveryFillHasReadableDarkText() {
        for rgb in AvatarStyle.paletteRGB {
            XCTAssertGreaterThanOrEqual(AvatarStyle.contrastRatio(rgb, AvatarStyle.textRGB), 4.5)
        }
    }
}

// MARK: - Lobby rules

final class LobbyRuleDraftTests: XCTestCase {
    private let current = LobbyRuleDraft(headStartS: 60, timeLimitMinutes: 30, revealIntervalS: 60)

    func testReadsTheDraftFromTimersAndConvertsTheLimitToMinutes() {
        let timers = TimersDTO(
            headStartS: 90, timeLimitS: 45 * 60, revealIntervalS: 120, nextRevealInS: nil, zone: nil
        )
        XCTAssertEqual(
            LobbyRuleDraft(timers: timers),
            LobbyRuleDraft(headStartS: 90, timeLimitMinutes: 45, revealIntervalS: 120)
        )
    }

    func testSendsOnlyChangedFields() {
        var draft = current
        draft.headStartS = 90
        XCTAssertEqual(draft.overrides(against: current), ["head_start": ["duration": .int(90)]])
        draft.timeLimitMinutes = 20
        draft.revealIntervalS = 30
        XCTAssertEqual(
            draft.overrides(against: current),
            [
                "head_start": ["duration": .int(90)],
                "win": ["time_limit": .int(20)],
                "reveal_fuzzy": ["interval": .int(30)],
            ]
        )
        XCTAssertNil(current.overrides(against: current))
    }

    func testNeverSendsARevealIntervalWhenRevealsAreOff() {
        let off = LobbyRuleDraft(headStartS: 60, timeLimitMinutes: 30, revealIntervalS: nil)
        var draft = off
        draft.headStartS = 61
        XCTAssertEqual(draft.overrides(against: off), ["head_start": ["duration": .int(61)]])
    }

    func testHeadStartOffAtZeroDoesNotBlockAnUnrelatedEdit() {
        let off = LobbyRuleDraft(headStartS: 0, timeLimitMinutes: 30, revealIntervalS: 60)
        var draft = off
        draft.timeLimitMinutes = 20
        XCTAssertTrue(draft.errors(against: off).isEmpty)
        draft.headStartS = 5
        XCTAssertEqual(draft.errors(against: off).count, 1)
    }

    func testBoundariesAreAcceptedAndJustOutsideIsRejected() {
        XCTAssertTrue(LobbyRuleDraft(headStartS: 15, timeLimitMinutes: 5, revealIntervalS: 20).errors.isEmpty)
        XCTAssertTrue(LobbyRuleDraft(headStartS: 600, timeLimitMinutes: 180, revealIntervalS: 600).errors.isEmpty)
        XCTAssertEqual(LobbyRuleDraft(headStartS: 14, timeLimitMinutes: 30, revealIntervalS: 60).errors.count, 1)
        XCTAssertEqual(LobbyRuleDraft(headStartS: 601, timeLimitMinutes: 181, revealIntervalS: 19).errors.count, 3)
    }
}

// MARK: - Store: host edits in the lobby

@MainActor
final class LobbyEditStoreTests: XCTestCase {
    private func hostedLobby() -> (AppStore, FakeGameService) {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        return (store, fake)
    }

    func testHostChangesRulesAndTheViewFollows() async {
        let (store, _) = hostedLobby()
        let accepted = await store.updateLobbyRules(["head_start": ["duration": .int(90)]])
        XCTAssertTrue(accepted)
        XCTAssertEqual(store.match?.snapshot.timers?.headStartS, 90)
        XCTAssertEqual(store.note, "Rules updated.")
    }

    func testRulesEditKeepsRolesAndPlayers() async {
        let (store, _) = hostedLobby()
        let before = store.match?.snapshot.players.map { [$0.playerId.uuidString, $0.role.rawValue] }
        _ = await store.updateLobbyRules(["win": ["time_limit": .int(20)]])
        let after = store.match?.snapshot.players.map { [$0.playerId.uuidString, $0.role.rawValue] }
        XCTAssertEqual(before, after)
    }

    func testEditAfterStartIsRejectedAsWrongPhase() async throws {
        let (store, fake) = hostedLobby()
        guard let gameID = store.match?.snapshot.gameId else { return XCTFail("Expected a match") }
        let started = try fake.advanceToActive(gameID: gameID)
        store.apply(started)
        let accepted = await store.updateLobbyRules(["head_start": ["duration": .int(90)]])
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.note, "Rules can only change in the lobby.")
    }

    func testRadiusOutsideTheCapIsRefusedBeforeTheNetwork() async {
        let (store, _) = hostedLobby()
        let accepted = await store.setLobbyRadius(3001)
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.note, ArenaValidator.radiusRangeMessage)
        let allowed = await store.setLobbyRadius(3000)
        XCTAssertTrue(allowed)
    }
}
