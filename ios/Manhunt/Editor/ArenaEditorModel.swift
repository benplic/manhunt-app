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
    var name = "New arena"
    var boundary = Polygon(vertices: [])
    var zones: [ArenaZone] = []
    /// Edge that the next play-area drop splits. Nil until the player picks one.
    var selectedEdge: Int?
    /// Vertex the next play-area drop moves.
    var vertexToMove: Int?
    private var safeCenter: GeoPoint?
    private var history: [Snapshot] = []

    /// True after the first tap of a safe-circle pair, before the radius tap.
    var hasPendingSafeCenter: Bool { safeCenter != nil }

    var issues: [ArenaIssue] {
        ArenaValidator.issues(
            in: Arena(id: UUID(), name: name, boundary: boundary, zones: zones)
        )
    }

    /// Load a saved outline as-is. Dropping points must not run, or the fourth
    /// vertex would be inserted into an edge instead of restored.
    func load(name: String, boundary: Polygon, zones: [ArenaZone]) {
        self.name = name
        self.boundary = boundary
        self.zones = zones
        safeCenter = nil
        selectedEdge = nil
        vertexToMove = nil
        history.removeAll()
    }

    func rename(_ name: String) {
        self.name = name
    }

    func selectEdge(_ index: Int) {
        guard boundary.vertices.count >= 3, boundary.vertices.indices.contains(index) else { return }
        selectedEdge = index
        vertexToMove = nil
    }

    func selectVertex(_ index: Int) {
        guard boundary.vertices.indices.contains(index) else { return }
        vertexToMove = index
        selectedEdge = nil
    }

    func dragVertex(at index: Int, to point: GeoPoint) {
        guard boundary.vertices.indices.contains(index) else { return }
        snapshot()
        boundary.vertices[index] = point
        vertexToMove = nil
    }

    func deleteVertex(at index: Int) {
        guard boundary.vertices.indices.contains(index) else { return }
        snapshot()
        boundary.vertices.remove(at: index)
        selectedEdge = nil
        vertexToMove = nil
    }

    func renameZone(id: UUID, to name: String) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
        zones[index].name = name
    }

    func deleteZone(id: UUID) {
        guard zones.contains(where: { $0.id == id }) else { return }
        snapshot()
        zones.removeAll { $0.id == id }
    }

    /// Once the play area has three vertices, a new point splits the selected
    /// edge. Appending it would let the player draw an hourglass.
    func addMapPoint(_ point: GeoPoint) {
        switch tool {
        case .playArea:
            if let index = vertexToMove {
                dragVertex(at: index, to: point)
                return
            }
            if boundary.vertices.count >= 3 {
                guard let edge = selectedEdge, boundary.vertices.indices.contains(edge) else {
                    selectedEdge = nearestEdge(to: point)
                    return
                }
                snapshot()
                boundary.vertices.insert(point, at: edge + 1)
                selectedEdge = nil
                return
            }
            snapshot()
            boundary.vertices.append(point)
        case .safeCircle:
            snapshot()
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
            snapshot()
            appendPolygonPoint(point, kind: .outOfBounds, name: "Out of bounds")
        case .seekerSpawn:
            snapshot()
            appendPolygonPoint(point, kind: .seekerSpawn, name: "Seeker spawn")
        }
    }

    func undo() {
        if let previous = history.popLast() {
            boundary = previous.boundary
            zones = previous.zones
            safeCenter = previous.safeCenter
            selectedEdge = previous.selectedEdge
            vertexToMove = previous.vertexToMove
            return
        }
        if safeCenter != nil {
            safeCenter = nil
        }
    }

    private func snapshot() {
        history.append(
            Snapshot(
                boundary: boundary,
                zones: zones,
                safeCenter: safeCenter,
                selectedEdge: selectedEdge,
                vertexToMove: vertexToMove
            )
        )
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

    /// Local meters, same scale as ArenaGeometry. Not haversine.
    private func nearestEdge(to point: GeoPoint) -> Int? {
        let vertices = boundary.vertices
        guard vertices.count >= 2 else { return nil }
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for index in vertices.indices {
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            let distance = distance(from: point, toSegmentStart: start, end: end)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private func distance(from point: GeoPoint, toSegmentStart start: GeoPoint, end: GeoPoint) -> Double {
        let endEast = eastMeters(from: start, to: end)
        let endNorth = northMeters(from: start, to: end)
        let pointEast = eastMeters(from: start, to: point)
        let pointNorth = northMeters(from: start, to: point)
        let lengthSquared = endEast * endEast + endNorth * endNorth
        if lengthSquared < 0.0001 {
            return ArenaGeometry.meters(from: point, to: start)
        }
        let raw = (pointEast * endEast + pointNorth * endNorth) / lengthSquared
        let t = min(1, max(0, raw))
        let deltaEast = pointEast - endEast * t
        let deltaNorth = pointNorth - endNorth * t
        return (deltaEast * deltaEast + deltaNorth * deltaNorth).squareRoot()
    }

    private func northMeters(from origin: GeoPoint, to point: GeoPoint) -> Double {
        (point.latitude - origin.latitude) * 111_320
    }

    private func eastMeters(from origin: GeoPoint, to point: GeoPoint) -> Double {
        let scale = cos(origin.latitude * .pi / 180)
        return (point.longitude - origin.longitude) * 111_320 * scale
    }

    private struct Snapshot {
        var boundary: Polygon
        var zones: [ArenaZone]
        var safeCenter: GeoPoint?
        var selectedEdge: Int?
        var vertexToMove: Int?
    }
}
