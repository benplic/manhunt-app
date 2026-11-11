import CoreLocation
import XCTest
@testable import Manhunt

/// Client navigation against FakeGameService. No network.
final class AppStoreTests: XCTestCase {
    @MainActor
    func testStartsSignedOutAndSignInOpensHome() {
        let store = AppStore.makePreview()
        XCTAssertEqual(store.screen, .signedOut)
        XCTAssertNil(store.session)
        store.signInPreview()
        XCTAssertEqual(store.screen, .home)
        XCTAssertEqual(store.session?.displayName, "Casey Lee")
    }

    @MainActor
    func testUnknownArenaIsAMissingArenaError() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: UUID(), presetID: "classic")
        XCTAssertEqual(store.lastError, .missingArena)
        XCTAssertEqual(store.screen, .home)
        XCTAssertNil(store.match)
    }

    @MainActor
    func testCreateThenStartBeforeRolesNeedsBothRoles() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertTrue(store.isHost)
        XCTAssertEqual(store.startMatch(), .needBothRoles)
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertEqual(store.lastError, .needBothRoles)
    }

    @MainActor
    func testMalformedJoinCodeNeverHitsTheService() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        XCTAssertEqual(store.join(code: "park4"), .invalidFormat)
        XCTAssertEqual(fake.joinCalls, 0)
        XCTAssertEqual(store.screen, .home)
    }

    @MainActor
    func testUnknownJoinCodeIsNotFound() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        XCTAssertEqual(store.join(code: "ABCDEF"), .notFound)
        XCTAssertEqual(fake.joinCalls, 1)
        XCTAssertEqual(store.screen, .home)
    }

    @MainActor
    func testPark42JoinsAsANonHost() {
        let store = AppStore.makePreview()
        store.signInPreview()
        XCTAssertNil(store.join(code: "park42"))
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertEqual(store.joinCode, "PARK42")
        XCTAssertFalse(store.isHost)
    }

    @MainActor
    func testSignOutDropsTheMatch() {
        let store = AppStore.makePreview()
        store.signInPreview()
        _ = store.join(code: "PARK42")
        XCTAssertNotNil(store.match)
        store.signOut()
        XCTAssertEqual(store.screen, .signedOut)
        XCTAssertNil(store.match)
        XCTAssertNil(store.session)
    }

    @MainActor
    func testHeadStartWhileInTheLobbyOpensTheLiveMap() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        XCTAssertEqual(store.screen, .lobby)
        guard var view = store.match?.snapshot else { return XCTFail("Expected a lobby") }
        view.phase = .headStart
        store.apply(view)
        XCTAssertEqual(store.screen, .live)
    }

    @MainActor
    func testActivePhaseDropsTheStartLine() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.note = "The hunt is on."
        guard var view = store.match?.snapshot else { return XCTFail("Expected a lobby") }
        view.phase = .active
        store.apply(view)
        XCTAssertNil(store.note)
    }

    @MainActor
    func testSaveFailureStaysOnTheEditorWithTheServerReason() async {
        let fake = FakeGameService(arenas: [])
        fake.nextArenaError = ServiceError(
            code: .arenaInvalid,
            message: "Arena failed validation.",
            issues: [APIIssue(code: "self_intersection", name: "Play area")]
        )
        let store = AppStore(service: fake)
        store.beginNewArena()
        store.editor.addMapPoint(Fixtures.meters(x: 0, y: 0))
        store.editor.addMapPoint(Fixtures.meters(x: 40, y: 0))
        store.editor.addMapPoint(Fixtures.meters(x: 20, y: 30))
        store.saveArena()
        let deadline = Date().addingTimeInterval(2)
        while store.editor.notice == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.screen, .arenaEditor)
        XCTAssertEqual(store.editor.notice, "Play area crosses itself.")
        XCTAssertFalse(store.isSavingArena)
    }

    @MainActor
    func testEmptyPlayAreaSaveExplainsWhy() {
        let store = AppStore.makePreview()
        store.beginNewArena()
        store.saveArena()
        XCTAssertEqual(store.screen, .arenaEditor)
        XCTAssertEqual(store.editorWarning, "Play area needs at least three points.")
    }

    @MainActor
    func testEditZoneShapeSelectsThatPolygon() {
        let store = AppStore.makePreview()
        store.beginNewArena()
        store.editor.boundary = Polygon(vertices: [
            Fixtures.meters(x: 0, y: 0),
            Fixtures.meters(x: 80, y: 0),
            Fixtures.meters(x: 80, y: 80),
            Fixtures.meters(x: 0, y: 80),
        ])
        store.editor.tool = .outOfBounds
        store.editor.addMapPoint(Fixtures.meters(x: 10, y: 10))
        store.editor.addMapPoint(Fixtures.meters(x: 30, y: 10))
        store.editor.addMapPoint(Fixtures.meters(x: 20, y: 30))
        guard let id = store.editor.zones.first?.id else { return XCTFail("Expected a zone") }
        store.tool = .playArea
        store.editZoneShape(id: id)
        XCTAssertEqual(store.tool, .outOfBounds)
        XCTAssertEqual(store.editor.activeZoneID, id)
    }

    @MainActor
    func testPresetScreenWaitsForTheSchema() async {
        let fake = FakeGameService()
        fake.moduleFetchDelay = .milliseconds(150)
        let store = AppStore(service: fake)
        store.signInPreview()
        store.modules = []
        store.openPreset()
        XCTAssertEqual(store.screen, .home)
        let deadline = Date().addingTimeInterval(2)
        while store.screen != .preset, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.screen, .preset)
        XCTAssertFalse(store.modules.isEmpty)
    }

    @MainActor
    func testRandomizeThenStartOpensLive() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(hiderCount: 1)
        XCTAssertNil(store.startMatch())
        XCTAssertEqual(store.screen, .live)
    }

    @MainActor
    func testSignInShowsWakingCopyOnTheLiveClient() {
        // Isolate defaults so a failed wake retry cannot poison .standard for later tests.
        let suite = "manhunt.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(
            service: LiveGameService(baseURL: URL(string: "http://127.0.0.1:1")!),
            serverURL: "http://127.0.0.1:1",
            defaults: defaults
        )
        store.displayName = "Casey"
        store.signIn()
        XCTAssertEqual(store.note, WakeCopy.message)
    }

    @MainActor
    func testCycleRolePersistsOnTheFakeBeforeStart() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        let ids = store.players.map(\.id)
        XCTAssertEqual(ids.count, 2)
        // Both start unassigned. Cycle first to hider, second to seeker.
        store.cycleRole(ids[0])
        store.cycleRole(ids[1])
        store.cycleRole(ids[1])
        XCTAssertNil(store.startMatch())
        XCTAssertEqual(store.screen, .live)
    }

    @MainActor
    func testStartBeforeBothRolesSurfacesALobbyNote() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        XCTAssertEqual(store.startMatch(), .needBothRoles)
        XCTAssertEqual(store.note, AppStore.needBothRolesCopy)
        XCTAssertEqual(store.screen, .lobby)
    }

    @MainActor
    func testEditingArenaUpdatesInsteadOfDuplicating() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        let original = Arena.sampleSquare()
        store.editArena(original.id.uuidString)
        store.editor.name = "Updated Square"
        store.saveArena()
        // saveArena hops through an async Task; wait for the home screen.
        let deadline = Date().addingTimeInterval(1)
        while store.screen != .home, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.screen, .home)
        XCTAssertEqual(store.arenas.filter { $0.id == original.id }.count, 1)
        XCTAssertEqual(store.arenas.first { $0.id == original.id }?.name, "Updated Square")
        XCTAssertEqual(fake.storedArenas.filter { $0.id == original.id }.count, 1)
    }

    @MainActor
    func testLowBatteryThenEndSendsFinalFlag() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(hiderCount: 1)
        _ = store.startMatch()
        let loc = CLLocation(latitude: 40.66, longitude: -73.97)
        store.sendFix(from: loc, isFinal: false, battery: 0.04)
        XCTAssertEqual(fake.lastLocationFlag, "low_battery")
        store.sendFix(from: loc, isFinal: false, battery: 0.04)
        XCTAssertEqual(fake.lastLocationFlag, "normal")
        store.endMatch()
        XCTAssertEqual(fake.lastLocationFlag, "final")
    }

    @MainActor
    func testSignInWithAppleHitsTheFake() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInWithApple(identityToken: "identity-token")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.appleSignIns, 1)
        XCTAssertEqual(store.screen, .home)
    }

    @MainActor
    func testOutsideDecoyKeepsPickingAndSurfacesTheNote() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(hiderCount: 1)
        _ = store.startMatch()
        // Force the viewer into the hider seat with enough points for decoy.
        guard var snapshot = store.match?.snapshot else {
            return XCTFail("Expected a live match")
        }
        snapshot.you.role = .hider
        snapshot.you.points = 200
        snapshot.phase = .active
        store.match?.snapshot = snapshot

        store.buyPower(SamplePark.powerUps.first { $0.id == "decoy" }!)
        XCTAssertTrue(store.decoyPicking)

        // Client PowerUpRules.targetOutside fires before purchase is sent.
        store.dropDecoy(at: VisualPoint(latitude: 1.0, longitude: 1.0))
        XCTAssertTrue(store.decoyPicking)
        XCTAssertEqual(store.note, "Decoy has to sit inside the play area.")
    }

    @MainActor
    func testJoinShowsTheServerMessage() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        _ = store.join(code: "HUNT42")
        XCTAssertEqual(store.joinMessage, "No game is using that code.")
    }

    @MainActor
    func testLeaveResultsDropsTheLiveNote() {
        let store = AppStore.makePreview()
        store.note = "Taunt sent. Seekers can see you for a few seconds."
        store.screen = .results
        store.leaveResults()
        XCTAssertNil(store.note)
        XCTAssertEqual(store.screen, .home)
    }

    @MainActor
    func testLeaveClearsTheMatchAndHitsTheService() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        XCTAssertNotNil(store.match)
        store.goHome()
        XCTAssertNil(store.match)
        XCTAssertEqual(store.screen, .home)
        let deadline = Date().addingTimeInterval(1)
        while fake.leaveCalls == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(fake.leaveCalls, 1)
    }

    @MainActor
    func testTauntDuringActiveRaisesPoints() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(hiderCount: 1)
        _ = store.startMatch()
        guard let gameID = store.match?.snapshot.gameId,
              let youID = store.match?.snapshot.you.playerId
        else {
            return XCTFail("Expected a match")
        }
        // Host may be seeker after randomize; force hider + active for the taunt path.
        _ = try fake.setRoleSync(gameID: gameID, playerID: youID, role: .hider)
        let view = try fake.advanceToActive(gameID: gameID)
        store.apply(view)
        let before = store.shownPoints
        store.taunt()
        let deadline = Date().addingTimeInterval(1)
        while store.shownPoints == before, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(store.shownPoints, before)
        XCTAssertEqual(store.note, "Taunt sent. Seekers can see you for a few seconds.")
    }

    @MainActor
    func testRemoveLobbyPlayerHitsTheService() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        let guest = store.players.first { !$0.isYou && !$0.isHost }
        XCTAssertNotNil(guest)
        store.removeLobbyPlayer(guest!.id)
        let deadline = Date().addingTimeInterval(1)
        while store.players.contains(where: { $0.id == guest!.id }), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.players.contains(where: { $0.id == guest!.id }))
    }

    @MainActor
    func testRefreshRotatesTheFakeToken() async throws {
        let fake = FakeGameService()
        _ = try await fake.signIn(displayName: "Casey")
        let first = fake.signInSync("Casey").refreshToken
        XCTAssertNotNil(first)
        let rotated = try await fake.refresh(refreshToken: first!)
        XCTAssertNotEqual(rotated.refreshToken, first)
        XCTAssertEqual(fake.refreshCalls, 1)
    }

    @MainActor
    func testPendingDeviceTokenRegistersAfterAuth() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.setPendingDeviceToken("deadbeef")
        XCTAssertNil(fake.lastDeviceToken)
        store.signInPreview()
        let deadline = Date().addingTimeInterval(1)
        while fake.lastDeviceToken == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(fake.lastDeviceToken, "deadbeef")
    }
}
