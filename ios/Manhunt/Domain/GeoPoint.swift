import Foundation

/// WGS84 point. Codable keys match the server arena JSON (`lat` / `lon`).
struct GeoPoint: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }
}

struct Polygon: Hashable, Codable, Sendable {
    var vertices: [GeoPoint]
}
