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

    // HomeView confirms Sign out in an alert before calling signOut(); that dialog is UI-only.
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
        store.randomizeRoles(seekerCount: 1)
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
        store.ageYears = "18"
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
    func testCycleRoleNeverAssignsOpen() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        let id = store.players[0].id
        store.cycleRole(id) // unassigned -> hider
        store.cycleRole(id) // hider -> seeker
        store.cycleRole(id) // seeker -> hider
        XCTAssertEqual(store.players[0].role, .hider)
        // Open is no longer in the cycle; seeker flips back to hider.
        XCTAssertNotEqual(store.players[0].role, .unassigned)
    }

    @MainActor
    func testOpenCurrentRulesHidesPresetManagement() async {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.openCurrentRules()
        // Wait for the async schema refresh + screen change.
        let deadline = Date().addingTimeInterval(2)
        while store.screen != .preset, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.screen, .preset)
        XCTAssertFalse(store.presetManagementEnabled)
    }

    @MainActor
    func testPresentNoteClearsAfterTTL() async {
        let store = AppStore.makePreview()
        store.presentNote("Force tag requires the active hunt phase.", ttlSeconds: 0.05)
        XCTAssertEqual(store.note, "Force tag requires the active hunt phase.")
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(store.note)
    }

    func testInstallationIDStablePerDefaults() {
        let suite = "manhunt.tests.installation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = InstallationID.current(defaults: defaults)
        let second = InstallationID.current(defaults: defaults)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testPlayerAvatarInitialsAndStableColor() {
        XCTAssertEqual(PlayerAvatar.initials(from: "Casey Lee"), "CL")
        XCTAssertEqual(PlayerAvatar.initials(from: "Quinn"), "Q")
        let a = PlayerAvatar.fillColor(for: "player-1")
        let b = PlayerAvatar.fillColor(for: "player-1")
        let c = PlayerAvatar.fillColor(for: "player-2")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
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
        store.randomizeRoles(seekerCount: 1)
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
        store.randomizeRoles(seekerCount: 1)
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

    // LobbyView / LiveGameView confirm Leave this hunt? before goHome(); that dialog is UI-only.
    @MainActor
    func testRematchOpensANewLobbyWithAFreshGameId() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        let endedID = store.match?.snapshot.gameId
        XCTAssertNotNil(endedID)
        store.endMatch()
        XCTAssertEqual(store.screen, .results)
        store.timeline = [
            TimelineEventDTO(seq: 1, type: "game_ended", payload: TimelinePayloadDTO(text: "done"))
        ]
        store.rematch()
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertTrue(store.isHost)
        XCTAssertNotEqual(store.match?.snapshot.gameId, endedID)
        XCTAssertEqual(store.match?.snapshot.phase, .lobby)
        XCTAssertTrue(store.timeline.isEmpty)
        XCTAssertNotEqual(store.joinCode, "")
    }

    @MainActor
    func testGuestRematchBeforeHostSurfacesRematchNotReady() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        _ = store.join(code: "PARK42")
        fake.markEnded(store.match!.snapshot.gameId)
        store.screen = .results
        store.rematch()
        XCTAssertEqual(store.screen, .results)
        XCTAssertEqual(store.lastError, .service(.rematchNotReady))
        XCTAssertTrue(store.note?.lowercased().contains("host") == true)
    }

    @MainActor
    func testGuestRematchJoinsHostLobby() throws {
        let fake = FakeGameService()
        let host = AppStore(service: fake)
        host.signInPreview()
        host.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        host.randomizeRoles(seekerCount: 1)
        _ = host.startMatch()
        host.endMatch()
        let endedID = host.match!.snapshot.gameId
        host.rematch()
        let rematchID = host.match!.snapshot.gameId
        XCTAssertNotEqual(rematchID, endedID)

        _ = fake.signInSync("Riley Chen")
        let guest = AppStore(service: fake)
        guest.session = Session(displayName: "Riley Chen", token: "fake")
        guest.match = MatchHandle(
            snapshot: try fake.forceEndedGuestView(gameID: endedID),
            qrToken: nil
        )
        guest.screen = .results
        guest.rematch()
        XCTAssertEqual(guest.screen, .lobby)
        XCTAssertEqual(guest.match?.snapshot.gameId, rematchID)
        XCTAssertFalse(guest.isHost)
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
        store.randomizeRoles(seekerCount: 1)
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
        _ = try await fake.signIn(displayName: "Casey", installationId: "test-install", age: 18)
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

    @MainActor
    func testRenameBeforeCreateReauthsWithFieldName() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        let before = fake.signInCalls
        store.displayName = "  Morgan Reed  "
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        XCTAssertEqual(fake.signInCalls, before + 1)
        XCTAssertEqual(fake.lastSignInDisplayName, "Morgan Reed")
        XCTAssertEqual(store.session?.displayName, "Morgan Reed")
        XCTAssertEqual(store.displayName, "Morgan Reed")
        XCTAssertEqual(store.players.first(where: \.isYou)?.name, "Morgan Reed")
    }

    @MainActor
    func testRenameBeforeJoinReauthsWithFieldName() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        let before = fake.signInCalls
        store.displayName = "Riley Chen"
        XCTAssertNil(store.join(code: "PARK42"))
        XCTAssertEqual(fake.signInCalls, before + 1)
        XCTAssertEqual(fake.lastSignInDisplayName, "Riley Chen")
        XCTAssertEqual(store.session?.displayName, "Riley Chen")
        XCTAssertEqual(store.screen, .lobby)
    }

    @MainActor
    func testMatchingDisplayNameSkipsReauthBeforeJoin() {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        let before = fake.signInCalls
        store.displayName = "Casey Lee"
        XCTAssertNil(store.join(code: "PARK42"))
        XCTAssertEqual(fake.signInCalls, before)
        XCTAssertEqual(store.session?.displayName, "Casey Lee")
    }

    @MainActor
    func testSingleSendFailureDoesNotShowHiccupNote() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        store.handleSendFailure("ping failed")
        XCTAssertEqual(store.situation, .reconnecting)
        XCTAssertNotEqual(store.note, "Connection hiccup. Retrying…")
    }

    @MainActor
    func testTwoSendFailuresShowHiccupNote() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        store.handleSendFailure("one")
        store.handleSendFailure("two")
        XCTAssertEqual(store.note, "Connection hiccup. Retrying…")
        XCTAssertEqual(store.situation, .reconnecting)
    }

    @MainActor
    func testSuccessfulViewClearsHiccupNote() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        store.handleSendFailure("one")
        store.handleSendFailure("two")
        XCTAssertEqual(store.note, "Connection hiccup. Retrying…")
        guard var view = store.match?.snapshot else { return XCTFail("Expected match") }
        view.phase = .active
        store.apply(view)
        XCTAssertNil(store.note)
        XCTAssertNotEqual(store.situation, .reconnecting)
    }

    @MainActor
    func testReconnectShowsHiccupNoteAfterDebounce() async {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        store.hiccupDebounceSeconds = 0.05
        store.handleReconnect(true)
        XCTAssertEqual(store.situation, .reconnecting)
        XCTAssertNotEqual(store.note, "Connection hiccup. Retrying…")
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(store.note, "Connection hiccup. Retrying…")
    }

    @MainActor
    func testRemovedFromLobbyStopsReconnectAndGoesHome() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.situation = .reconnecting
        store.note = "Connection hiccup. Retrying…"
        store.handleRemovedFromLobby()
        XCTAssertEqual(store.screen, .home)
        XCTAssertNil(store.match)
        XCTAssertEqual(store.note, "You were removed from the lobby.")
        XCTAssertNotEqual(store.situation, .reconnecting)
    }

    @MainActor
    func testRescueWithOneTargetPurchasesImmediately() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        guard let gameID = store.match?.snapshot.gameId,
              let youID = store.match?.snapshot.you.playerId
        else {
            return XCTFail("Expected a match")
        }
        _ = try fake.setRoleSync(gameID: gameID, playerID: youID, role: .hider)
        var view = try fake.advanceToActive(gameID: gameID)
        store.apply(view)
        let other = store.match!.snapshot.players.first { $0.playerId != youID }!
        view = try fake.markConvertedFromHider(gameID: gameID, playerID: other.playerId)
        store.apply(view)
        view = try fake.grantPoints(gameID: gameID, points: 200)
        store.apply(view)
        guard let chip = store.dockPowerChips().first(where: { $0.id == "rescue" }) else {
            return XCTFail("Expected rescue chip")
        }
        store.buyPower(chip)
        XCTAssertFalse(store.showRescuePicker)
        let deadline = Date().addingTimeInterval(1)
        while store.note?.contains("Rescue") != true, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.note?.contains("Rescue"), true)
    }

    @MainActor
    func testMoveSafeBeginsMapPickForSingleCircleSafe() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        store.createMatch(arenaID: Arena.riversideSample().id, presetID: "classic")
        store.randomizeRoles(seekerCount: 1)
        _ = store.startMatch()
        guard let gameID = store.match?.snapshot.gameId,
              let youID = store.match?.snapshot.you.playerId
        else {
            return XCTFail("Expected a match")
        }
        _ = try fake.setRoleSync(gameID: gameID, playerID: youID, role: .seeker)
        var view = try fake.advanceToActive(gameID: gameID)
        store.apply(view)
        view = try fake.grantPoints(gameID: gameID, points: 200)
        store.apply(view)
        XCTAssertFalse(store.movableSafeZones.isEmpty, "Riverside should expose a circle safe")
        guard let chip = store.dockPowerChips().first(where: { $0.id == "move_safe" }) else {
            return XCTFail("Expected move_safe chip")
        }
        store.buyPower(chip)
        XCTAssertTrue(store.decoyPicking)
        XCTAssertEqual(store.mapPickPowerID, "move_safe")
        XCTAssertNotNil(store.moveSafeZoneId)
    }

    func testAgeUnder13SetsTooYoungNote() async {
        let fake = FakeGameService()
        do {
            _ = try await fake.signIn(displayName: "Casey", installationId: "test-install", age: 12)
            XCTFail("Expected tooYoung")
        } catch let error as ServiceError {
            XCTAssertEqual(error.code, .tooYoung)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    @MainActor
    func testSignInRejectsAgeUnder13WithNote() {
        let store = AppStore.makePreview()
        store.ageYears = "12"
        store.signIn()
        XCTAssertEqual(store.note, "Manhunt is not available for people under 13.")
        XCTAssertEqual(store.screen, .signedOut)
    }

    @MainActor
    func testDeleteAccountSignsOutAndHitsFake() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        XCTAssertNotNil(store.session?.token)
        store.deleteAccount()
        let deadline = Date().addingTimeInterval(1)
        while fake.deleteAccountCalls == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(fake.deleteAccountCalls, 1)
        XCTAssertEqual(store.screen, .signedOut)
        XCTAssertNil(store.session)
    }

    @MainActor
    func testSignInPersistsAgeYearsToDefaults() {
        let suite = "manhunt.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(service: FakeGameService(), defaults: defaults)
        store.ageYears = "24"
        store.displayName = "Casey"
        store.signIn()
        XCTAssertEqual(defaults.string(forKey: AppStore.ageYearsKey), "24")
    }

    @MainActor
    func testLaunchRestoresPersistedAgeYears() {
        let suite = "manhunt.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("27", forKey: AppStore.ageYearsKey)
        let store = AppStore(service: FakeGameService(), defaults: defaults)
        XCTAssertEqual(store.ageYears, "27")
    }

    @MainActor
    func testRenameReauthUsesStoredAgeWhenFieldEmpty() async throws {
        let suite = "manhunt.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("29", forKey: AppStore.ageYearsKey)
        let capture = CapturingLiveGameService()
        let store = AppStore(service: capture, defaults: defaults)
        store.arenas = [Arena.sampleSquare()]
        store.session = Session(displayName: "Casey", token: "old")
        store.displayName = "Morgan Reed"
        store.ageYears = ""
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        let deadline = Date().addingTimeInterval(2)
        while capture.lastSignInAge == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(capture.lastSignInAge, 29)
        XCTAssertNotEqual(capture.lastSignInAge, 18)
    }

    @MainActor
    func testMissingAgeRefusesRenameReauthWithoutSendingEighteen() async throws {
        let suite = "manhunt.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let capture = CapturingLiveGameService()
        let store = AppStore(service: capture, defaults: defaults)
        store.arenas = [Arena.sampleSquare()]
        store.session = Session(displayName: "Casey", token: "old")
        store.displayName = "Morgan Reed"
        store.ageYears = ""
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(capture.lastSignInAge)
        XCTAssertEqual(
            store.note,
            "Enter your age on the sign-in screen before creating or joining a game."
        )
    }
}

/// Non-fake `GameService` that records dev sign-in age for live-path store tests.
private final class CapturingLiveGameService: GameService {
    let joinCalls = 0
    private(set) var lastSignInAge: Int?

    private var stub: ServiceError {
        ServiceError(code: .internal, message: "stub")
    }

    func signIn(displayName: String, installationId: String, age: Int) async throws -> AuthOut {
        _ = installationId
        lastSignInAge = age
        let user = UserDTO(id: UUID(), displayName: displayName)
        return AuthOut(
            accessToken: "test",
            expiresAt: "2099-01-01T00:00:00Z",
            user: user,
            refreshToken: "refresh"
        )
    }

    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthOut {
        throw stub
    }

    func me() async throws -> UserDTO { throw stub }
    func deleteAccount() async throws { throw stub }
    func registerDeviceToken(_ token: String) async throws { throw stub }
    func arenas() async throws -> [Arena] { throw stub }
    func createArena(_ arena: Arena) async throws -> Arena { throw stub }
    func updateArena(_ arena: Arena) async throws -> Arena { throw stub }
    func deleteArena(id: UUID) async throws { throw stub }
    func createGame(
        arenaID: UUID,
        presetID: String,
        overrides: [String: [String: RuleValue]]
    ) async throws -> PlayerViewDTO {
        throw stub
    }
    func timeline(gameID: UUID) async throws -> [TimelineEventDTO] { throw stub }
    func join(code: String) async throws -> PlayerViewDTO { throw stub }
    func randomizeRoles(gameID: UUID, seekerCount: Int) async throws -> PlayerViewDTO { throw stub }
    func setRole(gameID: UUID, playerID: UUID, role: PlayerRole) async throws -> PlayerViewDTO { throw stub }
    func start(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func pause(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func resume(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func end(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func rematch(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func leave(gameID: UUID) async throws { throw stub }
    func removePlayer(gameID: UUID, playerID: UUID) async throws -> PlayerViewDTO { throw stub }
    func undoTag(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func ackSafety(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func taunt(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func view(gameID: UUID) async throws -> PlayerViewDTO { throw stub }
    func claimQR(gameID: UUID, token: String) async throws { throw stub }
    func purchase(
        gameID: UUID,
        powerID: String,
        extra: [String: Double],
        targetPlayerId: String?,
        zoneId: String?
    ) async throws -> PlayerViewDTO {
        throw stub
    }
    func demo(gameID: UUID, action: String, params: [String: RuleValue]) async throws -> PlayerViewDTO {
        throw stub
    }
    func fetchModules() async throws -> [VisualModule] { throw stub }
    func savePreset(name: String, modules: [String: [String: RuleValue]]) async throws -> SavedPresetDTO {
        throw stub
    }
    func updatePreset(
        id: String,
        name: String,
        modules: [String: [String: RuleValue]]
    ) async throws -> SavedPresetDTO {
        throw stub
    }
    func deletePreset(id: String) async throws { throw stub }
    func savedPresets() async throws -> [SavedPresetDTO] { throw stub }
    func refresh(refreshToken: String) async throws -> AuthOut { throw stub }
}
