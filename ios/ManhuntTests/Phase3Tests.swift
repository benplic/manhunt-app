import XCTest
@testable import Manhunt

final class Phase3Tests: XCTestCase {
    func testHintLineShowsBandMetersAndBearing() {
        let hint = HintDTO(band: "hot", meters: 30, name: "Riley", bearingDeg: 0)
        XCTAssertEqual(HintCopy.line(role: .seeker, hint: hint), "Riley is hot, 30 m, N")
        XCTAssertEqual(HintCopy.cardinal(for: 90), "E")
        XCTAssertEqual(HintCopy.cardinal(for: 180), "S")
        XCTAssertEqual(HintCopy.cardinal(for: 270), "W")
    }

    func testClearedHintSaysNoneYet() {
        XCTAssertEqual(HintCopy.line(role: .seeker, hint: nil), "No hint yet.")
        XCTAssertEqual(HintCopy.line(role: .seeker, hint: HintDTO(band: nil, meters: nil, name: nil, bearingDeg: nil)), "No hint yet.")
    }

    func testHiderDoesNotSeeWarmth() {
        let hint = HintDTO(band: "burning", meters: 4, name: "Jordan", bearingDeg: 90)
        XCTAssertEqual(HintCopy.line(role: .hider, hint: hint), "Warmth is hidden from you.")
    }

    func testHintHelpMatchesRevealMode() {
        XCTAssertEqual(HintCopy.hintsHelp(locationMode: "hot_cold", hintsEnabled: false), "Hints are always on in Hot/cold.")
        XCTAssertEqual(HintCopy.hintsHelp(locationMode: "precise", hintsEnabled: true), "Hints are off in Precise.")
        XCTAssertEqual(HintCopy.hintsHelp(locationMode: "fuzzy", hintsEnabled: true), "Hints are on with Fuzzy.")
        XCTAssertEqual(
            HintCopy.hintsHelp(locationMode: "fuzzy", hintsEnabled: false),
            "Hints are off while the Fuzzy Hints toggle is off."
        )
    }

    func testHeadStartChrome() {
        XCTAssertEqual(
            HeadStartChrome.kind(phase: .headStart, role: .seeker, seekerLock: "locked_map"),
            .fullMap
        )
        XCTAssertEqual(
            HeadStartChrome.kind(phase: .headStart, role: .seeker, seekerLock: nil),
            .fullMap
        )
        XCTAssertEqual(
            HeadStartChrome.kind(phase: .headStart, role: .seeker, seekerLock: "spawn_zone"),
            .spawnZone
        )
        XCTAssertEqual(
            HeadStartChrome.kind(phase: .headStart, role: .hider, seekerLock: "spawn_zone"),
            .none
        )
        XCTAssertEqual(
            HeadStartChrome.kind(phase: .active, role: .seeker, seekerLock: "spawn_zone"),
            .none
        )
    }

    func testFullMapLockHidesTheFloatingNotice() {
        XCTAssertFalse(HeadStartChrome.showsFloatingNotice(.fullMap))
        XCTAssertTrue(HeadStartChrome.showsFloatingNotice(.spawnZone))
        XCTAssertTrue(HeadStartChrome.showsFloatingNotice(.none))
    }
}
