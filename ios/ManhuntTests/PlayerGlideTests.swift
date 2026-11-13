import XCTest
@testable import Manhunt

final class PlayerGlideTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000)

    private func pin(_ id: String, x: Double, y: Double = 0) -> VisualPlayer {
        let p = Fixtures.meters(x: x, y: y)
        return VisualPlayer(id: id, name: id, role: .hider, isYou: false, isHost: false,
                            point: VisualPoint(latitude: p.latitude, longitude: p.longitude),
                            points: 0, earned: 0)
    }
    private func eastMeters(_ point: VisualPoint?) -> Double? { point.map { $0.longitude * 111_320 } }

    func testNewPlayerAppearsWhereItIs() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 40)], now: t0)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0))!, 40, accuracy: 0.01)
    }

    func testPinGlidesInAStraightLineOverTheSnapshotGap() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1)))!, 0, accuracy: 0.01)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1.5)))!, 5, accuracy: 0.01)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(2)))!, 10, accuracy: 0.01)
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(9)))!, 10, accuracy: 0.01)
    }

    func testRetargetMidGlideStartsFromTheDrawnPoint() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        glide.retarget([pin("a", x: 20)], now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1.5)))!, 5, accuracy: 0.01)
    }

    func testUnchangedTargetDoesNotRestartTheGlide() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1.4))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1.5)))!, 5, accuracy: 0.01)
    }

    func testBigJumpTeleportsAndRemovedPlayersAreForgotten() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0), pin("b", x: 0)], now: t0)
        glide.retarget([pin("a", x: 400)], now: t0.addingTimeInterval(1))
        XCTAssertEqual(eastMeters(glide.point(for: "a", at: t0.addingTimeInterval(1)))!, 400, accuracy: 0.01)
        XCTAssertNil(glide.point(for: "b", at: t0.addingTimeInterval(1)))
    }

    func testSettledOnlyAfterEveryGlideFinishes() {
        var glide = PlayerGlide()
        glide.retarget([pin("a", x: 0)], now: t0)
        glide.retarget([pin("a", x: 10)], now: t0.addingTimeInterval(1))
        XCTAssertFalse(glide.isSettled(at: t0.addingTimeInterval(1.5)))
        XCTAssertTrue(glide.isSettled(at: t0.addingTimeInterval(2.1)))
    }
}
