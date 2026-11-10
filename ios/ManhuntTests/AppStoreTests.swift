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
        let store = AppStore(
            service: LiveGameService(baseURL: URL(string: "http://127.0.0.1:1")!),
            serverURL: "http://127.0.0.1:1"
        )
        store.displayName = "Casey"
        store.signIn()
        XCTAssertEqual(store.note, WakeCopy.message)
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
    func testOutsideDecoyKeepsPickingAndSurfacesTheNote() async {
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

        store.dropDecoy(at: VisualPoint(latitude: 1.0, longitude: 1.0))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store.decoyPicking)
        XCTAssertEqual(store.note, "Decoy has to sit inside the play area.")
    }
}
