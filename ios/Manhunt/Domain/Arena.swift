import Foundation

enum ZoneKind: String, Codable, Hashable, Sendable {
    case safe
    case outOfBounds = "out_of_bounds"
    case seekerSpawn = "seeker_spawn"
}

enum ZoneShape: Hashable, Sendable, Codable {
    case polygon(Polygon)
    case circle(center: GeoPoint, radiusMeters: Double)

    enum CodingKeys: String, CodingKey {
        case type
        case vertices
        case center
        case radiusMeters = "radius_m"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "circle" {
            self = .circle(
                center: try container.decode(GeoPoint.self, forKey: .center),
                radiusMeters: try container.decode(Double.self, forKey: .radiusMeters)
            )
        } else {
            self = .polygon(Polygon(vertices: try container.decode([GeoPoint].self, forKey: .vertices)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .polygon(polygon):
            try container.encode("polygon", forKey: .type)
            try container.encode(polygon.vertices, forKey: .vertices)
        case let .circle(center, radiusMeters):
            try container.encode("circle", forKey: .type)
            try container.encode(center, forKey: .center)
            try container.encode(radiusMeters, forKey: .radiusMeters)
        }
    }
}

struct ArenaZone: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var name: String
    var kind: ZoneKind
    var shape: ZoneShape
}

struct CircleBoundary: Codable, Hashable, Sendable {
    var center: GeoPoint
    var radiusMeters: Double

    enum CodingKeys: String, CodingKey {
        case center
        case radiusMeters = "radius_m"
    }
}

struct Arena: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var name: String
    var boundary: Polygon
    var zones: [ArenaZone]
    var version: Int?
    var boundaryCircle: CircleBoundary?

    enum CodingKeys: String, CodingKey {
        case id, name, boundary, zones, version
        case boundaryCircle = "boundary_circle"
    }

    init(
        id: UUID,
        name: String,
        boundary: Polygon,
        zones: [ArenaZone],
        version: Int? = nil,
        boundaryCircle: CircleBoundary? = nil
    ) {
        self.id = id
        self.name = name
        self.boundary = boundary
        self.zones = zones
        self.version = version
        self.boundaryCircle = boundaryCircle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        // Server JSON stores the play area as a vertex list, not a wrapped Polygon.
        if let vertices = try? container.decode([GeoPoint].self, forKey: .boundary) {
            boundary = Polygon(vertices: vertices)
        } else {
            boundary = try container.decode(Polygon.self, forKey: .boundary)
        }
        zones = try container.decodeIfPresent([ArenaZone].self, forKey: .zones) ?? []
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        boundaryCircle = try container.decodeIfPresent(CircleBoundary.self, forKey: .boundaryCircle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(boundary.vertices, forKey: .boundary)
        try container.encode(zones, forKey: .zones)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(boundaryCircle, forKey: .boundaryCircle)
    }

    /// Equator-flat 200 m square used by tests and the fake service.
    static func sampleSquare() -> Arena {
        func meters(x: Double, y: Double) -> GeoPoint {
            GeoPoint(latitude: y / 111_320, longitude: x / 111_320)
        }
        return Arena(
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

    static let riversideID = UUID(uuidString: "00000000-0000-0000-0000-00000000AA01")!
    static let schoolyardID = UUID(uuidString: "00000000-0000-0000-0000-00000000AA02")!

    /// Prospect Park sample used by FakeGameService and the home list.
    static func riversideSample() -> Arena {
        Arena(
            id: riversideID,
            name: "Riverside Green",
            boundary: Polygon(vertices: [
                GeoPoint(latitude: 40.66355, longitude: -73.96995),
                GeoPoint(latitude: 40.66320, longitude: -73.96785),
                GeoPoint(latitude: 40.66155, longitude: -73.96735),
                GeoPoint(latitude: 40.66025, longitude: -73.96835),
                GeoPoint(latitude: 40.66015, longitude: -73.97015),
                GeoPoint(latitude: 40.66185, longitude: -73.97075),
            ]),
            zones: [
                ArenaZone(
                    id: UUID(uuidString: "00000000-0000-0000-0000-00000000BB01")!,
                    name: "Gazebo",
                    kind: .safe,
                    shape: .circle(
                        center: GeoPoint(latitude: 40.66215, longitude: -73.96915),
                        radiusMeters: 42
                    )
                ),
            ]
        )
    }

    static func schoolyardSample() -> Arena {
        Arena(
            id: schoolyardID,
            name: "Schoolyard",
            boundary: Polygon(vertices: [
                GeoPoint(latitude: 40.67240, longitude: -73.97720),
                GeoPoint(latitude: 40.67235, longitude: -73.97540),
                GeoPoint(latitude: 40.67090, longitude: -73.97530),
                GeoPoint(latitude: 40.67085, longitude: -73.97710),
            ]),
            zones: []
        )
    }

    func asVisual(place: String = "") -> VisualArena {
        VisualArena(
            id: id.uuidString,
            name: name,
            place: place,
            boundary: boundary.vertices.map { VisualPoint(latitude: $0.latitude, longitude: $0.longitude) },
            zones: zones.map { $0.asVisual() },
            boundaryCircle: boundaryCircle
        )
    }
}

/// The live map draws the server snapshot. A phone with no snapshot yet keeps its local arena.
enum MatchMap {
    static func arena(snapshot: Arena?, local: VisualArena) -> VisualArena {
        if let snapshot {
            return snapshot.asVisual(place: snapshot.name)
        }
        return local
    }
}

extension ArenaZone {
    func asVisual() -> VisualZone {
        switch shape {
        case let .circle(center, radiusMeters):
            return VisualZone(
                id: id.uuidString,
                name: name,
                kind: visualKind,
                points: [VisualPoint(latitude: center.latitude, longitude: center.longitude)],
                radiusMeters: radiusMeters
            )
        case let .polygon(polygon):
            return VisualZone(
                id: id.uuidString,
                name: name,
                kind: visualKind,
                points: polygon.vertices.map { VisualPoint(latitude: $0.latitude, longitude: $0.longitude) },
                radiusMeters: nil
            )
        }
    }

    private var visualKind: VisualZone.Kind {
        switch kind {
        case .safe: return .safe
        case .outOfBounds: return .outOfBounds
        case .seekerSpawn: return .spawn
        }
    }
}

enum ArenaIssue: Equatable {
    case selfIntersection(String)
    case playAreaTooSmall
    case playAreaRadiusInvalid
    case outsidePlayArea(String)
}
