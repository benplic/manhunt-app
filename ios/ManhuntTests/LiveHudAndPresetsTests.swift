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
}
