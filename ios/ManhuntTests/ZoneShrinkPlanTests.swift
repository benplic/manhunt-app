import XCTest
@testable import Manhunt

final class ZoneShrinkPlanTests: XCTestCase {
    func testZoneTimerDecodesTheShrinkInterval() throws {
        let json = #"{"radius_m": 210.0, "next_radius_m": 157.5, "shrinks_in_s": 42, "interval_s": 60}"#
        let zone = try JSONDecoder().decode(ZoneTimerDTO.self, from: Data(json.utf8))
        XCTAssertEqual(zone.intervalS, 60)
        let old = try JSONDecoder().decode(ZoneTimerDTO.self, from: Data(#"{"radius_m": 210.0}"#.utf8))
        XCTAssertNil(old.intervalS)
    }
}
