import Foundation

enum ArenaValidator {
    static func issues(in arena: Arena) -> [ArenaIssue] {
        var found: [ArenaIssue] = []
        if let circle = arena.boundaryCircle {
            if !circle.radiusMeters.isFinite || circle.radiusMeters < 30 || circle.radiusMeters > 2000 {
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
