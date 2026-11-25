import XCTest
@testable import Manhunt

/// Mirrors `web/src/game/socketMeter.test.ts`. The mapping is the same on both platforms.
final class SocketMeterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func health(
        connected: Bool = false,
        failures: Int = 0,
        lastMessageAge: TimeInterval? = nil,
        network: Bool = true
    ) -> SocketHealth {
        SocketHealth(
            connected: connected,
            failureStreak: failures,
            lastMessageAt: lastMessageAge.map { now.addingTimeInterval(-$0) },
            networkAvailable: network
        )
    }

    func testFourBarsWhenConnectedAndTheLastMessageIsWithinTheWindow() {
        XCTAssertEqual(SocketMeter.reading(for: health(connected: true, lastMessageAge: 0), now: now).bars, 4)
        XCTAssertEqual(
            SocketMeter.reading(for: health(connected: true, lastMessageAge: SocketMeter.staleAfter), now: now).bars,
            4
        )
    }

    func testThreeBarsWhenConnectedButTheLastMessageIsOlderThanTheWindow() {
        let reading = SocketMeter.reading(
            for: health(connected: true, lastMessageAge: SocketMeter.staleAfter + 0.1),
            now: now
        )
        XCTAssertEqual(reading, SocketMeter.Reading(bars: 3, label: .slow))
    }

    func testAConnectedSocketThatHasHeardNothingIsQuiet() {
        XCTAssertEqual(SocketMeter.reading(for: health(connected: true), now: now).bars, 3)
    }

    func testTwoBarsOnTheFirstRetryAndWhileFirstConnecting() {
        XCTAssertEqual(SocketMeter.reading(for: health(failures: 0), now: now).bars, 2)
        XCTAssertEqual(
            SocketMeter.reading(for: health(failures: 1), now: now),
            SocketMeter.Reading(bars: 2, label: .reconnecting)
        )
    }

    func testOneBarForRepeatedFailures() {
        XCTAssertEqual(
            SocketMeter.reading(for: health(failures: 2), now: now),
            SocketMeter.Reading(bars: 1, label: .unstable)
        )
        XCTAssertEqual(
            SocketMeter.reading(for: health(failures: SocketMeter.downAfterFailures - 1), now: now).bars,
            1
        )
    }

    func testZeroBarsWhenDown() {
        XCTAssertEqual(
            SocketMeter.reading(for: health(failures: SocketMeter.downAfterFailures), now: now),
            SocketMeter.Reading(bars: 0, label: .down)
        )
    }

    func testZeroBarsWithNoNetworkEvenOnTheFirstFailure() {
        XCTAssertEqual(SocketMeter.reading(for: health(failures: 1, network: false), now: now).bars, 0)
    }

    func testNoNetworkFlagIsIgnoredWhileConnected() {
        let reading = SocketMeter.reading(for: health(connected: true, lastMessageAge: 1, network: false), now: now)
        XCTAssertEqual(reading.bars, 4)
    }

    func testTheAccessibilityLabelNamesTheStateInWords() {
        XCTAssertEqual(SocketMeter.Reading(bars: 4, label: .good).accessibilityLabel, "Connection: good")
        XCTAssertEqual(SocketMeter.Reading(bars: 0, label: .down).accessibilityLabel, "Connection: down")
    }

    func testExplanationIncludesTheLastMessageAge() {
        XCTAssertEqual(
            SocketMeter.explanation(for: health(connected: true, lastMessageAge: 2.4), now: now),
            "Connected. Updates are arriving. Last update 2s ago."
        )
        XCTAssertEqual(
            SocketMeter.explanation(for: health(failures: 1), now: now),
            "Reconnecting to the hunt server. No update yet."
        )
    }

    func testAgeNeverGoesNegativeWhenTheClockMovesBack() {
        let future = SocketHealth(connected: true, failureStreak: 0, lastMessageAt: now.addingTimeInterval(30))
        XCTAssertEqual(SocketMeter.age(of: future, now: now), 0)
    }
}
