import XCTest
@testable import Manhunt

final class LiveHudAndPresetsTests: XCTestCase {
    func testArenaBoundaryCircleRoundTripsJSON() throws {
        let center = GeoPoint(latitude: 40.6616, longitude: -73.9688)
        let arena = Arena(
            id: UUID(),
            name: "Circle Meadow",
            boundary: Polygon(vertices: [
                GeoPoint(latitude: 40.662, longitude: -73.968),
                GeoPoint(latitude: 40.661, longitude: -73.968),
                GeoPoint(latitude: 40.661, longitude: -73.969),
            ]),
            zones: [],
            boundaryCircle: CircleBoundary(center: center, radiusMeters: 180)
        )
        let data = try JSONEncoder().encode(arena)
        let decoded = try JSONDecoder().decode(Arena.self, from: data)
        XCTAssertEqual(decoded.boundaryCircle, arena.boundaryCircle)
        XCTAssertEqual(decoded.asVisual().boundaryCircle, arena.boundaryCircle)
    }

    func testPlayerViewDecodesTimersWithAndWithoutZone() throws {
        let base = """
        {
          "game_id": "00000000-0000-0000-0000-000000000010",
          "join_code": "TACO42",
          "phase": "head_start",
          "phase_remaining_s": 45,
          "game_elapsed_s": 15,
          "time_limit_remaining_s": 1785,
          "you": {
            "player_id": "00000000-0000-0000-0000-000000000011",
            "role": "seeker",
            "status": "active",
            "is_host": true,
            "bounds": {"phase": "inside", "remaining_s": null},
            "safe_zone": null,
            "points": 100
          },
          "players": [],
          "reveals": [],
          "banners": [],
          "result": null
        }
        """
        let older = try JSONDecoder().decode(PlayerViewDTO.self, from: Data(base.utf8))
        XCTAssertNil(older.timers)

        let withTimers = """
        {
          "game_id": "00000000-0000-0000-0000-000000000010",
          "join_code": "TACO42",
          "phase": "head_start",
          "phase_remaining_s": 45,
          "game_elapsed_s": 15,
          "time_limit_remaining_s": 1785,
          "timers": {
            "head_start_s": 60,
            "time_limit_s": 1800,
            "reveal_interval_s": 60,
            "next_reveal_in_s": 45,
            "zone": {"radius_m": 400.0, "next_radius_m": 300.0, "shrinks_in_s": 345}
          },
          "you": {
            "player_id": "00000000-0000-0000-0000-000000000011",
            "role": "seeker",
            "status": "active",
            "is_host": true,
            "bounds": {"phase": "inside", "remaining_s": null},
            "safe_zone": null,
            "points": 100
          },
          "players": [],
          "reveals": [],
          "banners": [],
          "result": null
        }
        """
        let newer = try JSONDecoder().decode(PlayerViewDTO.self, from: Data(withTimers.utf8))
        XCTAssertEqual(newer.timers?.headStartS, 60)
        XCTAssertEqual(newer.timers?.timeLimitS, 1800)
        XCTAssertEqual(newer.timers?.revealIntervalS, 60)
        XCTAssertEqual(newer.timers?.nextRevealInS, 45)
        XCTAssertEqual(newer.timers?.zone?.radiusM, 400.0)
        XCTAssertEqual(newer.timers?.zone?.nextRadiusM, 300.0)
        XCTAssertEqual(newer.timers?.zone?.shrinksInS, 345)
    }

    func testOfflineSchemaIncludesZoneShrink() {
        let modules = ModuleForm.offlineModules()
        let shrink = modules.first { $0.id == "zone_shrink" }
        XCTAssertNotNil(shrink)
        XCTAssertEqual(shrink?.tracksEnabled, true)
        XCTAssertEqual(shrink?.enabled, false)
        XCTAssertEqual(shrink?.rows.map(\.id), ["every", "shrink_to", "min_radius_m"])
    }

    func testRulePresetsMatchSchemaBoundsAndRoundTrip() {
        let schemaModules = ModuleForm.offlineModules()
        let winRow = schemaModules.first { $0.id == "win" }?.rows.first { $0.id == "time_limit" }
        let hsRow = schemaModules.first { $0.id == "head_start" }?.rows.first { $0.id == "duration" }
        let pingRow = schemaModules.first { $0.id == "reveal_fuzzy" }?.rows.first { $0.id == "interval" }

        for preset in RulePreset.allCases {
            var modules = schemaModules
            preset.apply(to: &modules)
            XCTAssertEqual(RulePreset.matching(modules: modules), preset)

            if case let .stepper(min, max, step, _, _) = winRow?.control {
                let val = Double(preset.roundMinutes)
                XCTAssertTrue(val >= min && val <= max)
                XCTAssertEqual((val - min).truncatingRemainder(dividingBy: step), 0, accuracy: 0.001)
            } else {
                XCTFail("Expected win.time_limit stepper")
            }
            if case let .stepper(min, max, step, _, _) = hsRow?.control {
                let val = Double(preset.headStartSeconds)
                XCTAssertTrue(val >= min && val <= max)
                XCTAssertEqual((val - min).truncatingRemainder(dividingBy: step), 0, accuracy: 0.001)
            } else {
                XCTFail("Expected head_start.duration stepper")
            }
            if case let .stepper(min, max, step, _, _) = pingRow?.control {
                let val = Double(preset.pingSeconds)
                XCTAssertTrue(val >= min && val <= max)
                XCTAssertEqual((val - min).truncatingRemainder(dividingBy: step), 0, accuracy: 0.001)
            } else {
                XCTFail("Expected reveal_fuzzy.interval stepper")
            }
        }

        var custom = schemaModules
        if let idx = custom.firstIndex(where: { $0.id == "win" }),
           let rIdx = custom[idx].rows.firstIndex(where: { $0.id == "time_limit" }) {
            custom[idx].rows[rIdx].number = 45
        }
        XCTAssertNil(RulePreset.matching(modules: custom))
    }

    func testPresetOverridesGatesZoneShrinkToCircleArenas() {
        var modules = ModuleForm.offlineModules()
        if let idx = modules.firstIndex(where: { $0.id == "zone_shrink" }) {
            modules[idx].enabled = true
        }
        let polygonArena = Arena.sampleSquare()
        let polyOverrides = PresetOverrides.from(modules: modules, arena: polygonArena)
        XCTAssertEqual(polyOverrides["zone_shrink"]?["enabled"], .bool(false))

        let circleArena = Arena(
            id: UUID(),
            name: "Circle",
            boundary: polygonArena.boundary,
            zones: [],
            boundaryCircle: CircleBoundary(
                center: GeoPoint(latitude: 40.66, longitude: -73.97),
                radiusMeters: 250
            )
        )
        let circleOverrides = PresetOverrides.from(modules: modules, arena: circleArena)
        XCTAssertEqual(circleOverrides["zone_shrink"]?["enabled"], .bool(true))
    }

    func testLobbyRulesSummaryFormatsTimers() {
        let plain = TimersDTO(headStartS: 60, timeLimitS: 1800, revealIntervalS: 60, nextRevealInS: 60, zone: nil)
        XCTAssertEqual(RulesSummary.line(timers: plain), "30 min · 1:00 head start · 1:00 pings")

        let shrinking = TimersDTO(
            headStartS: 30,
            timeLimitS: 900,
            revealIntervalS: 40,
            nextRevealInS: 40,
            zone: ZoneTimerDTO(radiusM: 250, nextRadiusM: 187.5, shrinksInS: 330)
        )
        XCTAssertEqual(
            RulesSummary.line(timers: shrinking),
            "15 min · 0:30 head start · 0:40 pings · Zone shrinks"
        )
    }

    func testCircleRingMatchesServerGoldenVertices() {
        let center = GeoPoint(latitude: 40.6616, longitude: -73.9688)
        let ring = ArenaEditorModel.circleRing(center: center, radiusMeters: 200.0)
        XCTAssertEqual(ring.count, 64)
        XCTAssertEqual(ring[0].latitude, 40.663396622350, accuracy: 1e-10)
        XCTAssertEqual(ring[0].longitude, -73.968800000000, accuracy: 1e-10)
        XCTAssertEqual(ring[16].latitude, 40.661600000000, accuracy: 1e-10)
        XCTAssertEqual(ring[16].longitude, -73.966431570597, accuracy: 1e-10)
        XCTAssertEqual(ring[32].latitude, 40.659803377650, accuracy: 1e-10)
        XCTAssertEqual(ring[32].longitude, -73.968800000000, accuracy: 1e-10)
        XCTAssertEqual(ring[48].latitude, 40.661600000000, accuracy: 1e-10)
        XCTAssertEqual(ring[48].longitude, -73.971168429403, accuracy: 1e-10)
    }

    func testCirclePlayAreaToolSetsBoundaryRefusesPolygonDropAndClearsWithUndo() {
        let editor = ArenaEditorModel()
        editor.tool = .playCircle
        let center = Fixtures.meters(x: 200, y: 200)
        let edge = Fixtures.meters(x: 200, y: 400)
        editor.addMapPoint(center)
        XCTAssertTrue(editor.hasPendingPlayCircleCenter)
        XCTAssertNil(editor.boundaryCircle)

        editor.addMapPoint(edge)
        XCTAssertFalse(editor.hasPendingPlayCircleCenter)
        XCTAssertEqual(editor.boundary.vertices.count, 64)
        XCTAssertEqual(editor.boundaryCircle?.center, center)
        XCTAssertEqual(editor.boundaryCircle?.radiusMeters ?? 0, 200, accuracy: 0.5)
        XCTAssertTrue(editor.issues.isEmpty)

        // Switching to polygon and dropping must NOT silently convert or mutate the circle.
        editor.tool = .playArea
        editor.addMapPoint(Fixtures.meters(x: 300, y: 300))
        XCTAssertNotNil(editor.boundaryCircle)
        XCTAssertEqual(editor.boundary.vertices.count, 64)
        XCTAssertNotNil(editor.notice)

        // Clear and undo.
        editor.clearPlayArea()
        XCTAssertNil(editor.boundaryCircle)
        XCTAssertTrue(editor.boundary.vertices.isEmpty)
        editor.undo()
        XCTAssertNotNil(editor.boundaryCircle)
        XCTAssertEqual(editor.boundary.vertices.count, 64)

        // Out-of-range circle radius fails validation.
        let small = ArenaEditorModel()
        small.tool = .playCircle
        small.addMapPoint(Fixtures.meters(x: 0, y: 0))
        small.addMapPoint(Fixtures.meters(x: 0, y: 10))
        XCTAssertTrue(small.issues.contains(.playAreaRadiusInvalid))
    }

    @MainActor
    func testAppStoreMapsPlayCircleToolAndSavesBoundaryCircle() async {
        let fake = FakeGameService(arenas: [])
        let store = AppStore(service: fake)
        store.beginNewArena()
        store.editor.name = "Circle Meadow"
        store.tool = .playCircle
        store.drop(at: VisualPoint(latitude: 40.6616, longitude: -73.9688))
        XCTAssertNotNil(store.draftCircleCenter)
        store.drop(at: VisualPoint(latitude: 40.6634, longitude: -73.9688))
        XCTAssertNotNil(store.draftBoundaryCircle)
        XCTAssertEqual(store.draftBoundary.count, 64)
        store.saveArena()
        let deadline = Date().addingTimeInterval(3)
        while fake.storedArenas.isEmpty && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNotNil(fake.storedArenas.last?.boundaryCircle)
        XCTAssertEqual(fake.storedArenas.last?.boundary.vertices.count, 64)
    }

    func testPhaseClockProgressHeadStartActiveAndDistances() {
        let hsView = PlayerViewDTO(
            gameId: UUID(),
            joinCode: "TACO42",
            phase: .headStart,
            phaseRemainingS: 45,
            gameElapsedS: 15,
            timeLimitRemainingS: 1785,
            timers: TimersDTO(
                headStartS: 60,
                timeLimitS: 1800,
                revealIntervalS: 60,
                nextRevealInS: 45,
                zone: ZoneTimerDTO(radiusM: 420, nextRadiusM: 315, shrinksInS: 345)
            ),
            you: YouDTO(
                playerId: UUID(),
                role: .seeker,
                status: .active,
                isHost: true,
                bounds: BoundsDTO(phase: "inside", remainingS: nil),
                safeZone: nil,
                points: 100
            ),
            players: [],
            reveals: [],
            banners: [],
            result: nil
        )
        let usClock = PhaseClock(snapshot: hsView, paused: false, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(usClock.primaryLabel, "Head start")
        XCTAssertEqual(usClock.primaryClock, "0:45")
        XCTAssertEqual(usClock.primaryProgress, 0.25, accuracy: 0.001)
        XCTAssertEqual(usClock.pingClock, "0:45")
        XCTAssertEqual(usClock.pingProgress, 0.25, accuracy: 0.001)
        XCTAssertEqual(usClock.zoneLine, "Zone 0.26 mi · shrinks in 5:45")

        let metricClock = PhaseClock(snapshot: hsView, paused: false, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(metricClock.zoneLine, "Zone 420 m · shrinks in 5:45")

        var activeView = hsView
        activeView.phase = .active
        activeView.phaseRemainingS = nil
        activeView.timeLimitRemainingS = 900
        activeView.timers = TimersDTO(
            headStartS: 60,
            timeLimitS: 1800,
            revealIntervalS: 60,
            nextRevealInS: 12,
            zone: ZoneTimerDTO(radiusM: 310, nextRadiusM: 259, shrinksInS: 42)
        )
        let activeUS = PhaseClock(snapshot: activeView, paused: false, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(activeUS.primaryLabel, "Time left")
        XCTAssertEqual(activeUS.primaryClock, "15:00")
        XCTAssertEqual(activeUS.primaryProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(activeUS.pingClock, "0:12")
        XCTAssertEqual(activeUS.pingProgress, 0.8, accuracy: 0.001)
        XCTAssertEqual(activeUS.zoneLine, "Zone 0.19 mi → 850 ft in 0:42")

        let pausedClock = PhaseClock(snapshot: activeView, paused: true, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(pausedClock.primaryLabel, "Paused")
    }

    @MainActor
    func testLiveUpdateFiltersNoiseAndExpiresAfterTwelveSeconds() {
        let store = AppStore.makePreview()
        let t0 = Date(timeIntervalSince1970: 1_000)

        store.recordLiveEvent(BannerDTO(bannerId: UUID(), tone: "info", title: "started", detail: "The hunt is on.", playerId: nil), now: t0)
        store.recordLiveEvent(BannerDTO(bannerId: UUID(), tone: "info", title: "player_joined", detail: "Riley joined.", playerId: nil), now: t0)
        store.recordLiveEvent(BannerDTO(bannerId: UUID(), tone: "info", title: "location", detail: "", playerId: nil), now: t0)
        XCTAssertNil(store.liveUpdate)

        let warnID = UUID()
        store.recordLiveEvent(
            BannerDTO(bannerId: warnID, tone: "warning", title: "zone_warning", detail: "Zone shrinks to 250 m in 1 min.", playerId: nil),
            now: t0
        )
        XCTAssertEqual(store.liveUpdate?.id, warnID)
        XCTAssertEqual(store.liveUpdate?.text, "Zone shrinks to 250 m in 1 min.")
        XCTAssertEqual(store.liveUpdate?.tone, "warning")

        store.clearExpiredLiveUpdate(now: t0.addingTimeInterval(11))
        XCTAssertNotNil(store.liveUpdate)

        store.clearExpiredLiveUpdate(now: t0.addingTimeInterval(12.5))
        XCTAssertNil(store.liveUpdate)
    }

    func testDockChromeShowsWaitingCardDuringHeadStartEvenWhenOutOfBounds() {
        let seekerWaiting = DockChrome.state(phase: .headStart, role: .seeker, remainingS: 124)
        XCTAssertEqual(
            seekerWaiting,
            .headStartWaiting(title: "Hiders are hiding", subtitle: "You're out in 2:04")
        )

        let hiderWaiting = DockChrome.state(phase: .headStart, role: .hider, remainingS: 45)
        XCTAssertEqual(
            hiderWaiting,
            .headStartWaiting(title: "Hide!", subtitle: "Seekers are released in 0:45")
        )

        XCTAssertEqual(DockChrome.state(phase: .active, role: .seeker, remainingS: nil), .activeTagging)
        XCTAssertEqual(DockChrome.state(phase: .active, role: .hider, remainingS: nil), .activeHider)

        let heldOutside = DockChrome.state(
            phase: .headStart,
            role: .seeker,
            remainingS: 60,
            spawnHolding: true,
            seekerOutsideSpawn: true
        )
        XCTAssertEqual(
            heldOutside,
            .headStartWaiting(
                title: "Get in the spawn zone",
                subtitle: "The countdown starts when every seeker is inside"
            )
        )
        let heldInside = DockChrome.state(
            phase: .headStart,
            role: .seeker,
            remainingS: 60,
            spawnHolding: true,
            seekerOutsideSpawn: false
        )
        XCTAssertEqual(
            heldInside,
            .headStartWaiting(
                title: "Waiting on seekers",
                subtitle: "The countdown starts when every seeker is inside"
            )
        )
    }

    @MainActor
    func testFlashlightTogglesAndAutoTurnsOffOnLifecycleEvents() {
        let torch = FakeTorch()
        let store = AppStore(service: FakeGameService(), torch: torch)
        store.signInPreview()
        store.createMatch(arenaID: Arena.sampleSquare().id, presetID: "classic")
        store.randomizeRoles(hiderCount: 1)
        _ = store.startMatch()

        store.toggleFlashlight()
        XCTAssertTrue(store.flashlightOn)
        XCTAssertEqual(torch.calls, [true])

        store.handleScenePhase(isBackground: true)
        XCTAssertFalse(store.flashlightOn)
        XCTAssertEqual(torch.calls, [true, false])

        store.toggleFlashlight()
        XCTAssertTrue(store.flashlightOn)
        store.leaveMatchThenHome()
        XCTAssertFalse(store.flashlightOn)

        store.toggleFlashlight()
        XCTAssertTrue(store.flashlightOn)
        store.signOut()
        XCTAssertFalse(store.flashlightOn)

        let brokenTorch = FakeTorch()
        brokenTorch.errorToThrow = TorchError.unavailable
        let brokenStore = AppStore(service: FakeGameService(), torch: brokenTorch)
        brokenStore.toggleFlashlight()
        XCTAssertFalse(brokenStore.flashlightOn)
        XCTAssertEqual(brokenStore.note, TorchError.unavailable.localizedDescription)

        brokenStore.tapVoicePlaceholder()
        XCTAssertEqual(brokenStore.note, "Voice is coming soon.")
    }
}

private final class FakeTorch: TorchControlling {
    var isAvailable: Bool = true
    var calls: [Bool] = []
    var errorToThrow: Error?

    func setOn(_ on: Bool) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        calls.append(on)
    }
}
