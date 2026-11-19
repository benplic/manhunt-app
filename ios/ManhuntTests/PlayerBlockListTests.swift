import XCTest
@testable import Manhunt

final class PlayerBlockListTests: XCTestCase {
    func testBlockPersistsAcrossInstances() {
        let suite = "manhunt.tests.block.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var list = PlayerBlockList(defaults: defaults)
        XCTAssertFalse(list.isBlocked("player-a"))
        list.block("player-a")
        XCTAssertTrue(list.isBlocked("player-a"))

        let reloaded = PlayerBlockList(defaults: defaults)
        XCTAssertTrue(reloaded.isBlocked("player-a"))
    }

    func testReportMailURLIncludesGamePlayerAndName() {
        let game = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let player = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let url = PlayerReportMail.url(
            gameID: game,
            playerID: player,
            displayName: "Riley",
            supportEmail: "support@example.com"
        )
        XCTAssertNotNil(url)
        let decoded = url!.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains("11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(decoded.contains("22222222-2222-2222-2222-222222222222"))
        XCTAssertTrue(decoded.contains("Riley"))
        XCTAssertTrue(decoded.contains("game_id"))
        XCTAssertTrue(decoded.contains("player_id"))
        XCTAssertTrue(decoded.contains("display_name"))
    }
}