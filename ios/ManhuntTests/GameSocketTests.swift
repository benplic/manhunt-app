import XCTest
@testable import Manhunt

final class GameSocketTests: XCTestCase {
    func testRemovedEnvelopeStopsReconnectAndFiresCallback() {
        let socket = GameSocket()
        var removedCalls = 0
        socket.onRemoved = { removedCalls += 1 }

        let payload = #"{"type":"removed","data":{"reason":"host_removed"}}"#
        socket.handle(Data(payload.utf8))

        XCTAssertTrue(socket.isStopped)
        XCTAssertEqual(removedCalls, 1)

        // A second removed / close must not re-fire.
        socket.handle(Data(payload.utf8))
        socket.noteServerClosed(code: 4403)
        XCTAssertEqual(removedCalls, 1)
    }

    func testCloseCode4403StopsReconnectAndFiresCallback() {
        let socket = GameSocket()
        var removedCalls = 0
        socket.onRemoved = { removedCalls += 1 }

        socket.noteServerClosed(code: 4403)

        XCTAssertTrue(socket.isStopped)
        XCTAssertEqual(removedCalls, 1)
    }

    func testOtherCloseCodesDoNotStopReconnect() {
        let socket = GameSocket()
        var removedCalls = 0
        socket.onRemoved = { removedCalls += 1 }

        socket.noteServerClosed(code: 1000)

        XCTAssertFalse(socket.isStopped)
        XCTAssertEqual(removedCalls, 0)
    }
}
