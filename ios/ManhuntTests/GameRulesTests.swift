import XCTest
@testable import Manhunt

/// Edge cases covered here: empty input, ambiguous join-code characters, boundary
/// points, concave play areas, tiny zones, self-intersection, and GPS accuracy
/// wider than the out-of-bounds margin.
final class GameRulesTests: XCTestCase {
    func testJoinCodeNormalizesAndRejectsAmbiguousCharacters() {
        XCTAssertEqual(JoinCode.normalize(" park42 "), "PARK42")
        XCTAssertTrue(JoinCode.isValid("PARK42"))
        XCTAssertFalse(JoinCode.isValid("PARK4"))
        XCTAssertFalse(JoinCode.isValid("PARK4O"))
        XCTAssertFalse(JoinCode.isValid("PARK41"))
        XCTAssertFalse(JoinCode.isValid("PARK4I"))
        XCTAssertFalse(JoinCode.isValid(""))

        var rng = SplitMix64(state: 7)
        let generated = JoinCode.generate(using: &rng)
        XCTAssertTrue(JoinCode.isValid(generated))
        XCTAssertEqual(generated.count, 6)
    }

    func testSquareContainsCenterAndBoundaryButNotTheBayOfAConcaveRing() {
        let square = Polygon(vertices: [
            Fixtures.meters(x: 0, y: 0),
            Fixtures.meters(x: 200, y: 0),
            Fixtures.meters(x: 200, y: 200),
            Fixtures.meters(x: 0, y: 200),
        ])
        XCTAssertTrue(ArenaGeometry.contains(Fixtures.meters(x: 100, y: 100), in: square))
        XCTAssertTrue(ArenaGeometry.contains(Fixtures.meters(x: 0, y: 0), in: square))
        XCTAssertTrue(ArenaGeometry.contains(Fixtures.meters(x: 100, y: 0), in: square))
        XCTAssertFalse(ArenaGeometry.contains(Fixtures.meters(x: 100, y: -40), in: square))

        let concave = Polygon(vertices: [
            Fixtures.meters(x: 0, y: 0),
            Fixtures.meters(x: 100, y: 0),
            Fixtures.meters(x: 100, y: 20),
            Fixtures.meters(x: 20, y: 20),
            Fixtures.meters(x: 20, y: 80),
            Fixtures.meters(x: 100, y: 80),
            Fixtures.meters(x: 100, y: 100),
            Fixtures.meters(x: 0, y: 100),
        ])
        XCTAssertTrue(ArenaGeometry.contains(Fixtures.meters(x: 10, y: 50), in: concave))
        XCTAssertFalse(ArenaGeometry.contains(Fixtures.meters(x: 50, y: 50), in: concave))
    }

    func testMeterScaleMatchesOneThousandthOfADegreeAlongTheEquator() {
        let distance = ArenaGeometry.meters(
            from: GeoPoint(latitude: 0, longitude: 0),
            to: GeoPoint(latitude: 0.001, longitude: 0)
        )
        XCTAssertEqual(distance, 111.32, accuracy: 0.05)
    }

    func testValidatorRejectsABowtieAndZonesThatLeaveThePlayArea() {
        var bowtie = Fixtures.square()
        bowtie.boundary = Polygon(vertices: [
            Fixtures.meters(x: 0, y: 0),
            Fixtures.meters(x: 100, y: 100),
            Fixtures.meters(x: 0, y: 100),
            Fixtures.meters(x: 100, y: 0),
        ])
        XCTAssertTrue(ArenaValidator.issues(in: bowtie).contains(.selfIntersection("Play area")))

        var empty = Fixtures.square()
        empty.boundary = Polygon(vertices: [Fixtures.meters(x: 0, y: 0), Fixtures.meters(x: 1, y: 0)])
        XCTAssertTrue(ArenaValidator.issues(in: empty).contains(.playAreaTooSmall))

        var stray = Fixtures.square()
        stray.zones = [
            ArenaZone(
                id: UUID(),
                name: "Shed",
                kind: .outOfBounds,
                shape: .polygon(Polygon(vertices: [
                    Fixtures.meters(x: 400, y: 400),
                    Fixtures.meters(x: 420, y: 400),
                    Fixtures.meters(x: 410, y: 420),
                ]))
            ),
        ]
        XCTAssertTrue(ArenaValidator.issues(in: stray).contains(.outsidePlayArea("Shed")))

        var overhang = Fixtures.square()
        overhang.zones = [
            ArenaZone(
                id: UUID(),
                name: "Fountain",
                kind: .safe,
                shape: .circle(center: Fixtures.meters(x: 100, y: 100), radiusMeters: 500)
            ),
        ]
        XCTAssertTrue(ArenaValidator.issues(in: overhang).contains(.outsidePlayArea("Fountain")))

        var tiny = Fixtures.square()
        tiny.zones = [
            ArenaZone(
                id: UUID(),
                name: "Bench",
                kind: .safe,
                shape: .circle(center: Fixtures.meters(x: 20, y: 20), radiusMeters: 3)
            ),
        ]
        XCTAssertEqual(ArenaValidator.issues(in: tiny), [])
    }

    func testOutOfBoundsWaitsForAccuracyAndIgnoresReadingsWorseThanThirtyMeters() {
        let boundary = Fixtures.square().boundary
        let inside = Fixtures.meters(x: 100, y: 100)
        let barelyOut = Fixtures.meters(x: 100, y: -10)
        let clearlyOut = Fixtures.meters(x: 100, y: -50)

        XCTAssertFalse(ArenaGeometry.isConfidentlyOutside(
            inside, accuracyMeters: 5, boundary: boundary, marginMeters: 5
        ))
        XCTAssertFalse(ArenaGeometry.isConfidentlyOutside(
            barelyOut, accuracyMeters: 10, boundary: boundary, marginMeters: 5
        ))
        XCTAssertTrue(ArenaGeometry.isConfidentlyOutside(
            clearlyOut, accuracyMeters: 8, boundary: boundary, marginMeters: 5
        ))
        XCTAssertFalse(ArenaGeometry.isConfidentlyOutside(
            clearlyOut, accuracyMeters: 31, boundary: boundary, marginMeters: 5
        ))
    }

    func testBoundsMachineWarnsThenCountsDownAndResetsBeforeThePenalty() {
        var machine = BoundsMachine()
        machine.receive(isOutside: true, countdownSeconds: 3)
        XCTAssertEqual(machine.phase, .warning)
        machine.receive(isOutside: true, countdownSeconds: 3)
        XCTAssertEqual(machine.phase, .countdown(remainingSeconds: 3))
        machine.receive(isOutside: false, countdownSeconds: 3)
        XCTAssertEqual(machine.phase, .inside)

        machine.receive(isOutside: true, countdownSeconds: 3)
        machine.receive(isOutside: true, countdownSeconds: 3)
        machine.receive(isOutside: true, countdownSeconds: 3)
        machine.receive(isOutside: true, countdownSeconds: 3)
        machine.receive(isOutside: true, countdownSeconds: 3)
        XCTAssertEqual(machine.phase, .penalized)
        machine.receive(isOutside: true, countdownSeconds: 3)
        XCTAssertEqual(machine.phase, .penalized)
        machine.receive(isOutside: false, countdownSeconds: 3)
        XCTAssertEqual(machine.phase, .inside)
    }

    func testRandomRolesHonorTheHiderCountAndEmptyInput() {
        let ids = (0..<4).map { _ in UUID() }
        var rng = SplitMix64(state: 99)
        let assigned = RoleAssigner.assign(playerIDs: ids, hiderCount: 1, using: &rng)
        XCTAssertEqual(assigned.count, 4)
        XCTAssertEqual(assigned.values.filter { $0 == .hider }.count, 1)
        XCTAssertEqual(assigned.values.filter { $0 == .seeker }.count, 3)

        var zero = SplitMix64(state: 1)
        let allSeekers = RoleAssigner.assign(playerIDs: ids, hiderCount: 0, using: &zero)
        XCTAssertTrue(allSeekers.values.allSatisfy { $0 == .seeker })

        var overflow = SplitMix64(state: 1)
        let allHiders = RoleAssigner.assign(playerIDs: ids, hiderCount: 90, using: &overflow)
        XCTAssertTrue(allHiders.values.allSatisfy { $0 == .hider })

        var unused = SplitMix64(state: 1)
        XCTAssertTrue(RoleAssigner.assign(playerIDs: [], hiderCount: 2, using: &unused).isEmpty)
    }

    func testPurchaseRulesRejectTheObviousIllegalBuys() {
        var request = PurchaseRequest(
            balance: 100,
            cost: 40,
            cooldownRemaining: 0,
            phase: .active,
            role: .hider,
            requiredRole: .hider,
            status: .active,
            requiresTarget: false,
            hasTarget: false
        )
        XCTAssertEqual(PowerUpRules.decide(request), .allowed)

        request.balance = 10
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.insufficientPoints))
        request.balance = 100
        request.cooldownRemaining = 4
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.coolingDown))
        request.cooldownRemaining = 0
        request.phase = .lobby
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.wrongPhase))
        request.phase = .active
        request.role = .seeker
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.wrongRole))
        request.role = .hider
        request.status = .eliminated
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.eliminated))
        request.status = .active
        request.requiresTarget = true
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.needsTarget))
        request.hasTarget = true
        XCTAssertEqual(PowerUpRules.decide(request), .allowed)
    }

    func testArenaEditorCommitsACircleOnTheSecondTapAndUndoRemovesIt() {
        let editor = ArenaEditorModel()
        editor.tool = .safeCircle
        editor.addMapPoint(Fixtures.meters(x: 10, y: 10))
        XCTAssertTrue(editor.zones.isEmpty)
        editor.addMapPoint(Fixtures.meters(x: 10, y: 25))
        XCTAssertEqual(editor.zones.count, 1)
        guard case let .circle(_, radius) = editor.zones[0].shape else {
            return XCTFail("Expected a circle")
        }
        XCTAssertEqual(radius, 15, accuracy: 0.5)

        editor.tool = .playArea
        editor.addMapPoint(Fixtures.meters(x: 0, y: 0))
        editor.addMapPoint(Fixtures.meters(x: 40, y: 0))
        editor.addMapPoint(Fixtures.meters(x: 20, y: 30))
        XCTAssertEqual(editor.boundary.vertices.count, 3)
        editor.undo()
        XCTAssertEqual(editor.boundary.vertices.count, 2)
        XCTAssertTrue(editor.issues.contains(.playAreaTooSmall))
    }
}
