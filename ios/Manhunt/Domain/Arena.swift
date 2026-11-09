import Foundation

enum ZoneKind: String, Codable, Hashable, Sendable {
    case safe
    case outOfBounds
    case seekerSpawn
}

enum ZoneShape: Hashable, Sendable {
    case polygon(Polygon)
    case circle(center: GeoPoint, radiusMeters: Double)
}

struct ArenaZone: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: ZoneKind
    var shape: ZoneShape
}

struct Arena: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var boundary: Polygon
    var zones: [ArenaZone]
}

enum ArenaIssue: Equatable {
    case selfIntersection(String)
    case playAreaTooSmall
    case outsidePlayArea(String)
}
