import Foundation

enum EditorTool: String, CaseIterable {
    case playArea
    case safeCircle
    case outOfBounds
    case seekerSpawn
}

/// Observable editor. Not @MainActor — GameRulesTests call it from a nonisolated context.
@Observable
final class ArenaEditorModel {
    var tool: EditorTool = .playArea
    var boundary = Polygon(vertices: [])
    var zones: [ArenaZone] = []
    private var safeCenter: GeoPoint?
    private var history: [(Polygon, [ArenaZone], GeoPoint?)] = []

    /// True after the first tap of a safe-circle pair, before the radius tap.
    var hasPendingSafeCenter: Bool { safeCenter != nil }

    var issues: [ArenaIssue] {
        ArenaValidator.issues(
            in: Arena(id: UUID(), name: "Draft", boundary: boundary, zones: zones)
        )
    }

    // TODO: Arena drawing currently appends vertices, which can bowtie into an hourglass.
    // Replace play-area editing with: select an edge, then drop a point that splits that edge.
    // Keep rejecting self-intersections until that interaction lands.
    func addMapPoint(_ point: GeoPoint) {
        history.append((boundary, zones, safeCenter))
        switch tool {
        case .playArea:
            boundary.vertices.append(point)
        case .safeCircle:
            if let center = safeCenter {
                let radius = ArenaGeometry.meters(from: center, to: point)
                zones.append(
                    ArenaZone(
                        id: UUID(),
                        name: "Safe zone",
                        kind: .safe,
                        shape: .circle(center: center, radiusMeters: radius)
                    )
                )
                safeCenter = nil
            } else {
                safeCenter = point
            }
        case .outOfBounds:
            appendPolygonPoint(point, kind: .outOfBounds, name: "Out of bounds")
        case .seekerSpawn:
            appendPolygonPoint(point, kind: .seekerSpawn, name: "Seeker spawn")
        }
    }

    func undo() {
        if let previous = history.popLast() {
            boundary = previous.0
            zones = previous.1
            safeCenter = previous.2
            return
        }
        if safeCenter != nil {
            safeCenter = nil
        }
    }

    private func appendPolygonPoint(_ point: GeoPoint, kind: ZoneKind, name: String) {
        if var last = zones.last, last.kind == kind, case .polygon(var polygon) = last.shape {
            polygon.vertices.append(point)
            last.shape = .polygon(polygon)
            zones[zones.count - 1] = last
        } else {
            zones.append(
                ArenaZone(
                    id: UUID(),
                    name: name,
                    kind: kind,
                    shape: .polygon(Polygon(vertices: [point]))
                )
            )
        }
    }
}
