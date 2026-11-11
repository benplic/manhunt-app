import Foundation

enum ArenaGeometry {
    /// Meters per degree of latitude; longitude is scaled by cos(lat).
    /// Matches the Swift tests (haversine is ~0.13 m off at 0.001°).
    static let metersPerDegree = 111_320.0

    static func meters(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat0 = (a.latitude + b.latitude) / 2 * .pi / 180
        let dy = (b.latitude - a.latitude) * metersPerDegree
        let dx = (b.longitude - a.longitude) * metersPerDegree * cos(lat0)
        return hypot(dx, dy)
    }

    static func contains(_ point: GeoPoint, in polygon: Polygon) -> Bool {
        let verts = polygon.vertices
        guard verts.count >= 3 else { return false }
        if isOnBoundary(point, polygon: polygon) { return true }
        // Even-odd ray cast. Boundary hits already returned true.
        var inside = false
        var j = verts.count - 1
        for i in verts.indices {
            let vi = verts[i]
            let vj = verts[j]
            let intersect =
                (vi.latitude > point.latitude) != (vj.latitude > point.latitude)
                && point.longitude < (vj.longitude - vi.longitude)
                    * (point.latitude - vi.latitude)
                    / (vj.latitude - vi.latitude + 1e-18)
                    + vi.longitude
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    /// A player is out of bounds only when they are farther outside than
    /// `accuracy + margin`. Readings worse than 30 m never count.
    static func isConfidentlyOutside(
        _ point: GeoPoint,
        accuracyMeters: Double,
        boundary: Polygon,
        marginMeters: Double
    ) -> Bool {
        if accuracyMeters > 30 { return false }
        let distance = distanceOutside(point, boundary: boundary)
        return distance > accuracyMeters + marginMeters
    }

    static func distanceOutside(_ point: GeoPoint, boundary: Polygon) -> Double {
        if contains(point, in: boundary) { return 0 }
        return distanceToEdges(point, polygon: boundary)
    }

    static func covers(zone: ArenaZone, playArea: Polygon) -> Bool {
        switch zone.shape {
        case let .polygon(polygon):
            guard polygon.vertices.count >= 3 else { return false }
            if !polygon.vertices.allSatisfy({ contains($0, in: playArea) }) {
                return false
            }
            // A zone that crosses the play-area edge is not fully inside.
            if edgesCross(polygon.vertices, playArea.vertices) {
                return false
            }
            // A chord can leave through a concave bay by touching vertices only,
            // which a proper edge-cross test misses. The midpoint of that chord is outside.
            for index in polygon.vertices.indices {
                let start = polygon.vertices[index]
                let end = polygon.vertices[(index + 1) % polygon.vertices.count]
                let midpoint = GeoPoint(
                    latitude: (start.latitude + end.latitude) / 2,
                    longitude: (start.longitude + end.longitude) / 2
                )
                if !contains(midpoint, in: playArea) {
                    return false
                }
            }
            return true
        case let .circle(center, radius):
            if !contains(center, in: playArea) { return false }
            return distanceToEdges(center, polygon: playArea) >= radius - 0.01
        }
    }

    static func selfIntersects(_ polygon: Polygon) -> Bool {
        let verts = polygon.vertices
        guard verts.count >= 4 else { return false }
        let n = verts.count
        for i in 0..<n {
            let a1 = verts[i]
            let a2 = verts[(i + 1) % n]
            for j in 0..<n {
                if abs(i - j) <= 1 { continue }
                if i == 0 && j == n - 1 { continue }
                if j == 0 && i == n - 1 { continue }
                if i > j { continue }
                let b1 = verts[j]
                let b2 = verts[(j + 1) % n]
                if segmentsIntersectProper(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private static func isOnBoundary(_ point: GeoPoint, polygon: Polygon) -> Bool {
        let verts = polygon.vertices
        var j = verts.count - 1
        for i in verts.indices {
            if onSegment(point, verts[j], verts[i]) { return true }
            j = i
        }
        return false
    }

    private static func distanceToEdges(_ point: GeoPoint, polygon: Polygon) -> Double {
        let verts = polygon.vertices
        guard verts.count >= 2 else { return .infinity }
        var best = Double.infinity
        var j = verts.count - 1
        for i in verts.indices {
            best = min(best, distanceToSegment(point, verts[j], verts[i]))
            j = i
        }
        return best
    }

    private static func distanceToSegment(_ p: GeoPoint, _ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat0 = a.latitude * .pi / 180
        let ax = 0.0
        let ay = 0.0
        let bx = (b.longitude - a.longitude) * metersPerDegree * cos(lat0)
        let by = (b.latitude - a.latitude) * metersPerDegree
        let px = (p.longitude - a.longitude) * metersPerDegree * cos(lat0)
        let py = (p.latitude - a.latitude) * metersPerDegree
        let ab2 = bx * bx + by * by
        if ab2 < 1e-9 { return hypot(px, py) }
        let t = max(0, min(1, (px * bx + py * by) / ab2))
        return hypot(px - t * bx, py - t * by)
    }

    private static func onSegment(_ p: GeoPoint, _ a: GeoPoint, _ b: GeoPoint) -> Bool {
        distanceToSegment(p, a, b) < 0.05
    }

    private static func edgesCross(_ a: [GeoPoint], _ b: [GeoPoint]) -> Bool {
        guard a.count >= 2, b.count >= 2 else { return false }
        for i in 0..<a.count {
            let a1 = a[i]
            let a2 = a[(i + 1) % a.count]
            for j in 0..<b.count {
                let b1 = b[j]
                let b2 = b[(j + 1) % b.count]
                if segmentsIntersectProper(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private static func segmentsIntersectProper(
        _ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint, _ d: GeoPoint
    ) -> Bool {
        let d1 = cross(a, b, c)
        let d2 = cross(a, b, d)
        let d3 = cross(c, d, a)
        let d4 = cross(c, d, b)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
            && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    private static func cross(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint) -> Double {
        (b.longitude - a.longitude) * (c.latitude - a.latitude)
            - (b.latitude - a.latitude) * (c.longitude - a.longitude)
    }
}
