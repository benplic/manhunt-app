import Foundation

enum ArenaValidator {
    /// Play circle radius limits. Keep in sync with the server (`PLAY_CIRCLE_*_M`)
    /// and the web radius inputs.
    static let minPlayRadiusMeters: Double = 30
    static let maxPlayRadiusMeters: Double = 3000

    /// Shown wherever the radius range is explained to a player.
    static let radiusRangeMessage = "Play area radius must be between 30 m and 3,000 m."

    static func isValidPlayRadius(_ radiusMeters: Double) -> Bool {
        radiusMeters.isFinite
            && radiusMeters >= minPlayRadiusMeters
            && radiusMeters <= maxPlayRadiusMeters
    }

    static func issues(in arena: Arena) -> [ArenaIssue] {
        var found: [ArenaIssue] = []
        if let circle = arena.boundaryCircle {
            if !isValidPlayRadius(circle.radiusMeters) {
                found.append(.playAreaRadiusInvalid)
                return found
            }
        }
        if arena.boundary.vertices.count < 3 {
            found.append(.playAreaTooSmall)
        } else if ArenaGeometry.selfIntersects(arena.boundary) {
            found.append(.selfIntersection("Play area"))
        }
        for zone in arena.zones {
            if arena.boundary.vertices.count >= 3,
               !ArenaGeometry.covers(zone: zone, playArea: arena.boundary) {
                found.append(.outsidePlayArea(zone.name))
            }
            if case let .polygon(polygon) = zone.shape, ArenaGeometry.selfIntersects(polygon) {
                found.append(.selfIntersection(zone.name))
            }
        }
        return found
    }
}
