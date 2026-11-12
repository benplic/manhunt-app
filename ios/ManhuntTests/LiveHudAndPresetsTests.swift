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
}
