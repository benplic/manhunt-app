import CoreLocation
import XCTest
@testable import Manhunt

final class DemoControlsTests: XCTestCase {
    func testPlayerViewDecodesDemoPayloadAndOmitsForNormalGame() throws {
        let withoutDemo = """
        {
          "game_id": "00000000-0000-0000-0000-000000000010",
          "join_code": "TACO42",
          "phase": "active",
          "phase_remaining_s": null,
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
        let plain = try JSONDecoder().decode(PlayerViewDTO.self, from: Data(withoutDemo.utf8))
        XCTAssertNil(plain.demo)

        let withDemo = """
        {
          "game_id": "00000000-0000-0000-0000-000000000010",
          "join_code": "PARK42",
          "phase": "lobby",
          "phase_remaining_s": null,
          "game_elapsed_s": 0,
          "time_limit_remaining_s": 1800,
          "you": {
            "player_id": "00000000-0000-0000-0000-000000000011",
            "role": "hider",
            "status": "active",
            "is_host": true,
            "bounds": {"phase": "inside", "remaining_s": null},
            "safe_zone": null,
            "points": 100
          },
          "players": [],
          "reveals": [],
          "banners": [],
          "result": null,
          "lobby_starts_in_s": 30,
          "demo": {
            "speed": 5,
            "lobby_hold": true,
            "seeker_lock": "spawn_zone",
            "controls_enabled": true,
            "virtual_location": {"lat": 40.6617, "lon": -73.9690},
            "bots": [
              {
                "player_id": "00000000-0000-0000-0000-000000000022",
                "display_name": "Riley Chen",
                "role": "seeker",
                "status": "active",
                "mode": "auto"
              }
            ]
          }
        }
        """
        let decoded = try JSONDecoder().decode(PlayerViewDTO.self, from: Data(withDemo.utf8))
        XCTAssertEqual(decoded.demo?.speed, 5)
        XCTAssertEqual(decoded.demo?.lobbyHold, true)
        XCTAssertEqual(decoded.demo?.seekerLock, "spawn_zone")
        XCTAssertEqual(decoded.demo?.controlsEnabled, true)
        XCTAssertEqual(decoded.demo?.virtualLocation, DemoPointDTO(lat: 40.6617, lon: -73.9690))
        XCTAssertEqual(decoded.demo?.bots.count, 1)
        XCTAssertEqual(decoded.demo?.bots.first?.displayName, "Riley Chen")
    }

    func testFakeGameServiceDemoActionsUpdateState() async throws {
        let fake = FakeGameService()
        _ = try await fake.signIn(displayName: "Casey Lee")
        let lobby = try await fake.joinDemoAsHost()
        XCTAssertEqual(lobby.demo?.controlsEnabled, true)

        let held = try await fake.demo(gameID: lobby.gameId, action: "lobby_hold", params: ["hold": .bool(true)])
        XCTAssertEqual(held.demo?.lobbyHold, true)

        let locked = try await fake.demo(
            gameID: lobby.gameId,
            action: "set_seeker_lock",
            params: ["mode": .string("locked_map")]
        )
        XCTAssertEqual(locked.demo?.seekerLock, "locked_map")

        let headStart = try await fake.demo(gameID: lobby.gameId, action: "end_phase", params: [:])
        XCTAssertEqual(headStart.phase, .headStart)

        let active = try await fake.demo(gameID: lobby.gameId, action: "end_phase", params: [:])
        XCTAssertEqual(active.phase, .active)

        let sped = try await fake.demo(gameID: lobby.gameId, action: "set_speed", params: ["speed": .int(5)])
        XCTAssertEqual(sped.demo?.speed, 5)

        let added = try await fake.demo(gameID: lobby.gameId, action: "add_points", params: ["amount": .int(100)])
        XCTAssertEqual(added.you.points, active.you.points + 100)

        let moved = try await fake.demo(
            gameID: lobby.gameId,
            action: "move_me",
            params: ["lat": .double(40.6620), "lon": .double(-73.9692)]
        )
        XCTAssertEqual(moved.demo?.virtualLocation, DemoPointDTO(lat: 40.6620, lon: -73.9692))
    }

    @MainActor
    func testAppStoreDemoPickingMutualExclusionAndFixSuppression() async throws {
        let fake = FakeGameService()
        let store = AppStore(service: fake)
        store.signInPreview()
        let view = try await fake.joinDemoAsHost()
        store.apply(view)

        XCTAssertTrue(store.isDemoGame)
        XCTAssertTrue(store.demoControlsEnabled)

        // Real phone GPS fixes are ignored when in a demo match.
        let fix = CLLocation(latitude: 37.3349, longitude: -122.0090)
        store.sendFix(from: fix, isFinal: false, battery: 0.5)
        XCTAssertNil(fake.lastLocationFlag)

        // Move-me pick mode cancels decoyPicking and updates virtual_location.
        store.decoyPicking = true
        store.beginDemoMovePick()
        XCTAssertFalse(store.decoyPicking)
        XCTAssertTrue(store.demoPicking)

        let ok = await store.performDemoAction(
            "move_me",
            params: ["lat": .double(40.6622), "lon": .double(-73.9693)],
            note: "Walking there…"
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(store.match?.snapshot.demo?.virtualLocation, DemoPointDTO(lat: 40.6622, lon: -73.9693))
    }
}
