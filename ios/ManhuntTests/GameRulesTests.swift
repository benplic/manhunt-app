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

    func testLocationFlagSendsLowBatteryOncePerDipAndFinalWins() {
        let first = LocationFlag.choose(battery: 0.04, isFinal: false, wasLow: false)
        XCTAssertEqual(first.flag, "low_battery")
        XCTAssertTrue(first.nowLow)
        let again = LocationFlag.choose(battery: 0.04, isFinal: false, wasLow: true)
        XCTAssertEqual(again.flag, "normal")
        let recovered = LocationFlag.choose(battery: 0.40, isFinal: false, wasLow: true)
        XCTAssertFalse(recovered.nowLow)
        let ended = LocationFlag.choose(battery: 0.04, isFinal: true, wasLow: true)
        XCTAssertEqual(ended.flag, "final")
        let unknown = LocationFlag.choose(battery: -1, isFinal: false, wasLow: false)
        XCTAssertEqual(unknown.flag, "normal")
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

        request.targetInsidePlayArea = false
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.targetOutside))
    }

    func testDecoyChipIsTappableWhenOnlyNeedsTarget() {
        let request = PurchaseRequest(
            balance: 100,
            cost: 60,
            cooldownRemaining: 0,
            phase: .active,
            role: .hider,
            requiredRole: .hider,
            status: .active,
            requiresTarget: true,
            hasTarget: false
        )
        XCTAssertEqual(PowerUpRules.decide(request), .denied(.needsTarget))
        XCTAssertTrue(PowerUpRules.chipIsTappable(request))
    }

    func testDecoyChipStaysGreyWhenPointsAreShort() {
        let request = PurchaseRequest(
            balance: 10,
            cost: 60,
            cooldownRemaining: 0,
            phase: .active,
            role: .hider,
            requiredRole: .hider,
            status: .active,
            requiresTarget: true,
            hasTarget: false
        )
        XCTAssertFalse(PowerUpRules.chipIsTappable(request))
    }

    @MainActor
    func testRadarSeekersFollowEffectsNotLocalToggle() {
        let store = AppStore.makePreview()
        store.match = MatchHandle(
            snapshot: PlayerViewDTO(
                gameId: UUID(),
                joinCode: "ABC123",
                phase: .active,
                phaseRemainingS: nil,
                gameElapsedS: 10,
                timeLimitRemainingS: 100,
                you: YouDTO(
                    playerId: UUID(),
                    role: .hider,
                    status: .active,
                    isHost: false,
                    bounds: BoundsDTO(phase: "inside", remainingS: nil),
                    safeZone: nil,
                    points: 80,
                    hint: nil,
                    effects: ["radar"],
                    cooldowns: nil
                ),
                players: [],
                reveals: [],
                banners: [],
                result: nil
            ),
            qrToken: nil
        )
        XCTAssertTrue(store.radarShowsSeekers)
        XCTAssertTrue(store.shouldShowSeekerPins)
        var cleared = store.match!
        cleared.snapshot.you.effects = []
        store.match = cleared
        XCTAssertFalse(store.radarShowsSeekers)
        // No server-sent seeker locations either — pins stay off.
        XCTAssertFalse(store.shouldShowSeekerPins)
    }

    func testPresetOverridesUseServerModuleIdsAndClampHeadStart() {
        var modules = ModuleForm.offlineModules()
        XCTAssertFalse(modules.isEmpty, "The offline schema should build the preset form.")
        if let index = modules.firstIndex(where: { $0.id == "head_start" }) {
            modules[index].enabled = false
            if let row = modules[index].rows.firstIndex(where: { $0.id == "duration" }) {
                modules[index].rows[row].number = 5
            }
        }
        let overrides = PresetOverrides.from(modules: modules)
        XCTAssertEqual(overrides["head_start"]?["enabled"], .bool(false))
        XCTAssertEqual(overrides["head_start"]?["duration"], .int(15))
        XCTAssertEqual(overrides["reveal_fuzzy"]?["display"], .int(10))
        XCTAssertEqual(overrides["win"]?["condition"], .string("either"))
        XCTAssertNil(overrides["reveal"])
    }

    func testSchemaFormRoundTripsASavedPreset() {
        var modules = ModuleForm.offlineModules()
        let duration = modules.first { $0.id == "head_start" }?.rows.first { $0.id == "duration" }
        guard case let .stepper(min, max, _, _, _) = duration?.control else {
            return XCTFail("Duration should be a stepper from the schema")
        }
        XCTAssertEqual(min, 15)
        XCTAssertEqual(max, 600)
        let index = modules.firstIndex { $0.id == "head_start" }!
        let row = modules[index].rows.firstIndex { $0.id == "duration" }!
        modules[index].rows[row].number = 45
        let payload = PresetOverrides.from(modules: modules)
        let restored = ModuleForm.apply(payload, to: ModuleForm.offlineModules())
        let again = restored.first { $0.id == "head_start" }?.rows.first { $0.id == "duration" }
        XCTAssertEqual(again?.number, 45)
    }

    @MainActor
    func testSavedPresetRoundTripsThroughTheService() async {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.modules = ModuleForm.offlineModules()
        store.presetName = "Park night"
        let index = store.modules.firstIndex { $0.id == "head_start" }!
        let row = store.modules[index].rows.firstIndex { $0.id == "duration" }!
        store.modules[index].rows[row].number = 45
        await store.savePreset()
        XCTAssertEqual(store.savedPresets.first?.name, "Park night")
        store.modules = ModuleForm.offlineModules()
        guard let saved = store.savedPresets.first else {
            return XCTFail("Expected a saved preset")
        }
        store.applySavedPreset(saved)
        let duration = store.modules.first { $0.id == "head_start" }?.rows.first { $0.id == "duration" }
        XCTAssertEqual(duration?.number, 45)
    }

    @MainActor
    func testReopeningPresetEditorKeepsInMemoryEdits() async {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.modules = ModuleForm.offlineModules()
        let index = store.modules.firstIndex { $0.id == "head_start" }!
        let row = store.modules[index].rows.firstIndex { $0.id == "duration" }!
        store.modules[index].rows[row].number = 45
        store.modules[index].enabled = false
        await store.refreshPresetEditor()
        let headStart = store.modules.first { $0.id == "head_start" }
        XCTAssertEqual(headStart?.enabled, false)
        XCTAssertEqual(headStart?.rows.first { $0.id == "duration" }?.number, 45)
    }

    func testPlayAreaDropSplitsTheSelectedEdge() {
        let editor = ArenaEditorModel()
        editor.tool = .playArea
        editor.addMapPoint(Fixtures.meters(x: 0, y: 0))
        editor.addMapPoint(Fixtures.meters(x: 100, y: 0))
        editor.addMapPoint(Fixtures.meters(x: 100, y: 100))
        XCTAssertEqual(editor.boundary.vertices.count, 3)
        // A fourth drop must not append. Appending is what draws an hourglass.
        editor.addMapPoint(Fixtures.meters(x: 50, y: -10))
        XCTAssertEqual(editor.boundary.vertices.count, 3)
        XCTAssertNotNil(editor.selectedEdge)
        editor.selectEdge(0)
        editor.addMapPoint(Fixtures.meters(x: 50, y: 0))
        XCTAssertEqual(editor.boundary.vertices.count, 4)
        XCTAssertEqual(editor.boundary.vertices[1].longitude, Fixtures.meters(x: 50, y: 0).longitude, accuracy: 1e-9)
        XCTAssertEqual(editor.boundary.vertices[2].longitude, Fixtures.meters(x: 100, y: 0).longitude, accuracy: 1e-9)
        XCTAssertNil(editor.issues.first { if case .selfIntersection = $0 { return true }; return false })
    }

    func testDragRenameAndDeleteVertex() {
        let editor = ArenaEditorModel()
        editor.tool = .playArea
        editor.addMapPoint(Fixtures.meters(x: 0, y: 0))
        editor.addMapPoint(Fixtures.meters(x: 40, y: 0))
        editor.addMapPoint(Fixtures.meters(x: 20, y: 30))
        editor.rename("Riverside")
        XCTAssertEqual(editor.name, "Riverside")
        let moved = Fixtures.meters(x: 5, y: 5)
        editor.dragVertex(at: 0, to: moved)
        XCTAssertEqual(editor.boundary.vertices[0].latitude, moved.latitude, accuracy: 1e-9)
        editor.deleteVertex(at: 2)
        XCTAssertEqual(editor.boundary.vertices.count, 2)
        editor.undo()
        XCTAssertEqual(editor.boundary.vertices.count, 3)

        editor.tool = .outOfBounds
        editor.addMapPoint(Fixtures.meters(x: 10, y: 10))
        let zoneID = editor.zones[0].id
        editor.renameZone(id: zoneID, to: "Creek")
        XCTAssertEqual(editor.zones[0].name, "Creek")
        editor.deleteZone(id: zoneID)
        XCTAssertTrue(editor.zones.isEmpty)
    }

    func testTimelineSortsThePlaytestEventsBySeq() {
        let events = [
            TimelineEventDTO(seq: 9, type: "signal_lost", payload: TimelinePayloadDTO(text: "Hider went dark.", tone: "safety")),
            TimelineEventDTO(seq: 2, type: "reveal", payload: TimelinePayloadDTO(text: "Hider pins are up.", tone: "info")),
            TimelineEventDTO(seq: 7, type: "tag", payload: TimelinePayloadDTO(text: "Seeker tagged Hider.", tone: "success")),
            TimelineEventDTO(seq: 4, type: "out_of_bounds", payload: TimelinePayloadDTO(text: "Hider was tagged out of bounds.", tone: "warning")),
        ]
        let ordered = TimelineOrder.sorted(events)
        XCTAssertEqual(ordered.map(\.type), ["reveal", "out_of_bounds", "tag", "signal_lost"])
        XCTAssertEqual(ordered.map(\.seq), [2, 4, 7, 9])
    }

    @MainActor
    func testUniversalLinkAndInviteQRBothJoin() {
        let store = AppStore.makePreview()
        let url = InviteLink.url(joinCode: "park42")
        XCTAssertEqual(url.absoluteString, "https://app.manhunt.ios/join/PARK42")
        XCTAssertNil(store.open(url: url))
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertEqual(store.joinCode, "PARK42")
        store.goHome()
        store.openInvite(url.absoluteString)
        XCTAssertEqual(store.screen, .lobby)
        XCTAssertEqual(store.joinCode, "PARK42")
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
