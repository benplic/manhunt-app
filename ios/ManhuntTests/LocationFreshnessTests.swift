import XCTest
@testable import Manhunt

final class LocationFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testFreshWhenTheLastUpdateIsRecent() {
        XCTAssertFalse(
            LocationFreshness.isStale(
                lastUpdateAt: now.addingTimeInterval(-5),
                startedAt: now.addingTimeInterval(-600),
                now: now,
                staleAfter: 30
            )
        )
    }

    func testStaleWhenNothingArrivedForLongerThanTheLimit() {
        XCTAssertTrue(
            LocationFreshness.isStale(
                lastUpdateAt: now.addingTimeInterval(-31),
                startedAt: now.addingTimeInterval(-600),
                now: now,
                staleAfter: 30
            )
        )
    }

    func testTheBoundaryItselfIsNotStale() {
        XCTAssertFalse(
            LocationFreshness.isStale(
                lastUpdateAt: now.addingTimeInterval(-30),
                startedAt: nil,
                now: now,
                staleAfter: 30
            )
        )
    }

    func testAStreamThatNeverProducedAnUpdateIsMeasuredFromItsStart() {
        XCTAssertTrue(
            LocationFreshness.isStale(lastUpdateAt: nil, startedAt: now.addingTimeInterval(-120), now: now, staleAfter: 30)
        )
        XCTAssertFalse(
            LocationFreshness.isStale(lastUpdateAt: nil, startedAt: now.addingTimeInterval(-10), now: now, staleAfter: 30)
        )
    }

    func testAStreamThatWasNeverStartedIsNotStale() {
        XCTAssertFalse(LocationFreshness.isStale(lastUpdateAt: nil, startedAt: nil, now: now, staleAfter: 30))
    }
}
