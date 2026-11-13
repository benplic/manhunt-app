import Foundation
@testable import Manhunt

enum Fixtures {
    /// Local flat projection at the equator so 1 meter is 1/111320 of a degree.
    static func meters(x: Double, y: Double) -> GeoPoint {
        GeoPoint(latitude: y / 111_320, longitude: x / 111_320)
    }

    static func square() -> Arena {
        Arena(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Square",
            boundary: Polygon(vertices: [
                meters(x: 0, y: 0),
                meters(x: 200, y: 0),
                meters(x: 200, y: 200),
                meters(x: 0, y: 200),
            ]),
            zones: []
        )
    }

    static func liveView(
        phase: MatchPhase = .active,
        elapsed: Int = 0,
        timeLimitRemaining: Int? = 1800,
        nextReveal: Int? = 60,
        zone: ZoneTimerDTO? = nil,
        role: PlayerRole = .hider
    ) -> PlayerViewDTO {
        PlayerViewDTO(
            gameId: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            joinCode: "PARK42",
            phase: phase,
            phaseRemainingS: phase == .headStart ? max(0, 60 - elapsed) : nil,
            gameElapsedS: elapsed,
            timeLimitRemainingS: timeLimitRemaining,
            timers: TimersDTO(
                headStartS: 60, timeLimitS: 1800, revealIntervalS: 60,
                nextRevealInS: nextReveal, zone: zone
            ),
            you: YouDTO(
                playerId: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
                role: role, status: .active, isHost: true,
                bounds: BoundsDTO(phase: "inside", remainingS: nil),
                safeZone: nil, points: 0
            ),
            players: [], reveals: [], banners: [], result: nil
        )
    }
}
