import XCTest
@testable import Manhunt

final class DisplayNameRulesTests: XCTestCase {
    func testBlockedNameRejected() {
        XCTAssertFalse(DisplayNameRules.isAllowed("hello retard"))
    }

    func testCleanNameAllowed() {
        XCTAssertTrue(DisplayNameRules.isAllowed("Casey Lee"))
    }

    func testBlockedTokenIsWholeWord() {
        XCTAssertTrue(DisplayNameRules.isAllowed("retarded")) // not the blocked token "retard"
    }
}