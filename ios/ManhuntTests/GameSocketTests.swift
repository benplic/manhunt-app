import XCTest
@testable import Manhunt

final class GameSocketTests: XCTestCase {
    func testEventEnvelopeDecodesStructuredTagFields() throws {
        let socket = GameSocket()
        var received: LiveEventDTO?
        socket.onEvent = { received = $0 }

        let payload = """
        {
          "type": "event",
          "data": {
            "seq": 41,
            "type": "tag",
            "text": "Riley was tagged by Morgan.",
            "tone": "danger",
            "player_id": "00000000-0000-0000-0000-000000000041",
            "announcement": "player_tagged",
            "subject_name": "Riley"
          }
        }
        """
        socket.handle(Data(payload.utf8))

        XCTAssertEqual(received?.seq, 41)
        XCTAssertEqual(received?.type, "tag")
        XCTAssertEqual(received?.text, "Riley was tagged by Morgan.")
        XCTAssertEqual(received?.tone, "danger")
        XCTAssertEqual(received?.playerId, UUID(uuidString: "00000000-0000-0000-0000-000000000041"))
        XCTAssertEqual(received?.announcement, "player_tagged")
        XCTAssertEqual(received?.subjectName, "Riley")
    }

    func testEventSequenceIsAStableIdentifierAndDuplicateIsNotDelivered() {
        let socket = GameSocket()
        var received: [LiveEventDTO] = []
        socket.onEvent = { received.append($0) }
        let payload = """
        {
          "type": "event",
          "data": {
            "seq": 42,
            "type": "tag",
            "text": "Riley was tagged.",
            "tone": "danger",
            "player_id": null,
            "announcement": "player_tagged",
            "subject_name": "Riley"
          }
        }
        """

        socket.handle(Data(payload.utf8))
        socket.handle(Data(payload.utf8))

        XCTAssertEqual(received.map(\.seq), [42])
        XCTAssertEqual(socket.lastSeq, 42)
    }

    func testEventSequenceResetsForANewGameButNotAReconnect() {
        let socket = GameSocket()
        var received: [Int] = []
        socket.onEvent = { received.append($0.seq) }
        let gameA = UUID()
        let gameB = UUID()

        socket.beginGame(gameA)
        socket.handle(eventEnvelope(seq: 9))
        socket.beginGame(gameA)
        socket.handle(eventEnvelope(seq: 9))
        socket.beginGame(gameB)
        socket.handle(eventEnvelope(seq: 1))

        XCTAssertEqual(received, [9, 1])
        XCTAssertEqual(socket.lastSeq, 1)
    }

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

    private func eventEnvelope(seq: Int) -> Data {
        Data(
            """
            {
              "type": "event",
              "data": {
                "seq": \(seq),
                "type": "tag",
                "text": "Riley was tagged.",
                "tone": "danger",
                "player_id": null,
                "announcement": "player_tagged",
                "subject_name": "Riley"
              }
            }
            """.utf8
        )
    }
}
