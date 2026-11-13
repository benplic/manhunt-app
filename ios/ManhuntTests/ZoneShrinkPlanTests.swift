import XCTest
@testable import Manhunt

final class ZoneShrinkPlanTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 3_000)

  /// Interval 60 s, ring 200 m shrinking to 150 m.
  private func visual(shrinksIn: Double?, next: Double? = 150, interval: Double? = 60) -> ZoneShrinkVisual {
    ZoneShrinkPlan.visual(radiusM: 200, nextRadiusM: next, shrinksInS: shrinksIn, intervalS: interval)
  }

    func testZoneTimerDecodesTheShrinkInterval() throws {
        let json = #"{"radius_m": 210.0, "next_radius_m": 157.5, "shrinks_in_s": 42, "interval_s": 60}"#
        let zone = try JSONDecoder().decode(ZoneTimerDTO.self, from: Data(json.utf8))
        XCTAssertEqual(zone.intervalS, 60)
        let old = try JSONDecoder().decode(ZoneTimerDTO.self, from: Data(#"{"radius_m": 210.0}"#.utf8))
        XCTAssertNil(old.intervalS)
    }

  func testNoPreviewBeforeTheHalfwayPoint() {
    let v = visual(shrinksIn: 40)
    XCTAssertNil(v.nextRadiusM)
    XCTAssertEqual(v.previewOpacity, 0)
    XCTAssertEqual(v.radiusM, 200)
  }

  func testDashedRingFadesInAfterHalfway() {
    XCTAssertEqual(visual(shrinksIn: 30).previewOpacity, 0, accuracy: 1e-9)
    let mid = visual(shrinksIn: 28.5)
    XCTAssertEqual(mid.previewOpacity, 0.5, accuracy: 1e-9)
    XCTAssertEqual(mid.nextRadiusM, 150)
    XCTAssertEqual(visual(shrinksIn: 20).previewOpacity, 1, accuracy: 1e-9)
    XCTAssertEqual(visual(shrinksIn: 20).radiusM, 200)
  }

  func testRingContractsDuringTheLastQuarterAndLandsOnTheNextRadius() {
    XCTAssertEqual(visual(shrinksIn: 15).radiusM, 200, accuracy: 1e-9)
    XCTAssertEqual(visual(shrinksIn: 7.5).radiusM, 175, accuracy: 1e-9)
    XCTAssertEqual(visual(shrinksIn: 0).radiusM, 150, accuracy: 1e-9)
    XCTAssertLessThan(visual(shrinksIn: 3).radiusM, visual(shrinksIn: 9).radiusM)
  }

  func testNothingToPreviewAtFinalSizeOrWithoutAnInterval() {
    XCTAssertEqual(visual(shrinksIn: nil, next: nil).previewOpacity, 0)
    XCTAssertEqual(visual(shrinksIn: 5, next: nil).radiusM, 200)
    let old = visual(shrinksIn: 5, interval: nil)
    XCTAssertEqual(old.radiusM, 200)
    XCTAssertNil(old.nextRadiusM)
    XCTAssertEqual(visual(shrinksIn: 5, interval: 0).radiusM, 200)
  }

  func testFirstIntervalThatIncludesHeadStartStaysQuiet() {
    let v = visual(shrinksIn: 120)
    XCTAssertNil(v.nextRadiusM)
    XCTAssertEqual(v.radiusM, 200)
  }

  func testClockExtrapolatesTheCountdownAndFreezesWhenPaused() {
    let zone = ZoneTimerDTO(radiusM: 200, nextRadiusM: 150, shrinksInS: 15, intervalS: 60)
    let running = ZoneShrinkClock(zone: zone, anchoredAt: t0, rate: 1)
    XCTAssertEqual(running.visual(at: t0).radiusM, 200, accuracy: 1e-9)
    XCTAssertLessThan(running.visual(at: t0.addingTimeInterval(0.8)).radiusM, 200)
    let paused = ZoneShrinkClock(zone: zone, anchoredAt: t0, rate: 0)
    XCTAssertEqual(paused.visual(at: t0.addingTimeInterval(0.8)).radiusM, 200, accuracy: 1e-9)
  }
}
