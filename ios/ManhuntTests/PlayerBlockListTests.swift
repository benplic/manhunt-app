import XCTest
@testable import Manhunt

final class PlayerBlockListTests: XCTestCase {
    func testBlockPersistsAcrossInstances() {
        let suite = "manhunt.tests.block.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var list = PlayerBlockList(defaults: defaults)
        XCTAssertFalse(list.isBlocked("player-a"))
        list.block("player-a", displayName: "Alex")
        XCTAssertTrue(list.isBlocked("player-a"))

        let reloaded = PlayerBlockList(defaults: defaults)
        XCTAssertTrue(reloaded.isBlocked("player-a"))
        XCTAssertEqual(reloaded.entries.first?.displayName, "Alex")
        XCTAssertEqual(reloaded.anonymizedName(for: "player-a"), "Blocked Player #1")
    }

    func testUnblockRemovesEntry() {
        let suite = "manhunt.tests.block.unblock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var list = PlayerBlockList(defaults: defaults)
        list.block("player-a", displayName: "Alex")
        list.block("player-b", displayName: "Blake")
        list.unblock("player-a")
        XCTAssertFalse(list.isBlocked("player-a"))
        XCTAssertEqual(list.anonymizedName(for: "player-b"), "Blocked Player #1")
    }

    func testLegacyIdArrayMigrates() {
        let suite = "manhunt.tests.block.migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["legacy-id"], forKey: "manhunt.blockedPlayerIds")

        let list = PlayerBlockList(defaults: defaults)
        XCTAssertTrue(list.isBlocked("legacy-id"))
        XCTAssertEqual(list.anonymizedName(for: "legacy-id"), "Blocked Player #1")
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
