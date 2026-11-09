import XCTest
@testable import Manhunt

@MainActor
final class AppStoreTests: XCTestCase {
    func testSignInCreateAndStartWalksTheScreens() {
        let store = AppStore.makePreview()
        XCTAssertEqual(store.screen, .signedOut)
        store.signInPreview()
        XCTAssertEqual(store.screen, .home)
        XCTAssertEqual(store.session?.displayName, "Casey Lee")

        store.createMatch(arenaID: UUID(), presetID: store.presets[0].id)
        XCTAssertEqual(store.lastError, .missingArena)
        XCTAssertEqual(store.screen, .home)

        store.createMatch(arenaID: store.arenas[0].id, presetID: store.presets[0].id)
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertTrue(JoinCode.isValid(store.match?.snapshot.joinCode ?? ""))
        XCTAssertGreaterThanOrEqual(store.match?.snapshot.players.count ?? 0, 2)
        XCTAssertEqual(store.startMatch(), .needBothRoles)

        store.randomizeRoles(hiderCount: 1)
        XCTAssertNil(store.startMatch())
        XCTAssertEqual(store.screen, .live)
        store.endMatch()
        XCTAssertEqual(store.screen, .results)
        store.leaveResults()
        XCTAssertEqual(store.screen, .home)
        XCTAssertNil(store.match)
    }

    func testJoinCodeErrorsAndTheKnownParkCode() {
        let store = AppStore.makePreview()
        store.signInPreview()
        XCTAssertEqual(store.join(code: "no"), .invalidFormat)
        XCTAssertEqual(store.screen, .home)
        XCTAssertEqual(store.join(code: "ABCDEF"), .notFound)
        XCTAssertNil(store.join(code: "park42"))
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertFalse(store.match?.snapshot.isHost ?? true)
        XCTAssertEqual(store.match?.snapshot.joinCode, "PARK42")
    }

    func testSignOutDropsTheMatch() {
        let store = AppStore.makePreview()
        store.signInPreview()
        store.createMatch(arenaID: store.arenas[0].id, presetID: store.presets[0].id)
        store.signOut()
        XCTAssertEqual(store.screen, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(store.match)
    }
}
