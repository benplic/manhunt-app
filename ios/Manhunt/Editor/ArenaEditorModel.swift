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
    /// Edge that the next drop splits on the closed play area or active zone.
    var selectedEdge: Int?
    /// Vertex the next play-area drop moves.
    var vertexToMove: Int?
    /// Open-chain points for Out / Spawn before the shape closes.
    private var pendingZoneVertices: [GeoPoint] = []
    /// After the third Out / Spawn drop, further points edit this zone until “New shape”.
    var activeZoneID: UUID?
    /// Last non-fatal editor message (clip warning, refused insert).
    var notice: String?
    private var pendingCircleCenter: GeoPoint?
    private var history: [Snapshot] = []

    /// True after the first tap of a safe-circle pair, before the radius tap.
    var hasPendingSafeCenter: Bool { pendingCircleCenter != nil }

    /// Dots and segment on the map before a polygon closes.
    var pendingVertices: [GeoPoint] {
        switch tool {
        case .playArea where boundary.vertices.count < 3:
            return boundary.vertices
        case .outOfBounds, .seekerSpawn:
            return pendingZoneVertices
        default:
            return []
        }
    }

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
        pendingCircleCenter = nil
        pendingZoneVertices = []
        activeZoneID = nil
        selectedEdge = nil
        vertexToMove = nil
        notice = nil
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
        if activeZoneID == id {
            activeZoneID = nil
        }
    }

    func beginNewShape() {
        pendingZoneVertices = []
        activeZoneID = nil
        selectedEdge = nil
        notice = nil
    }

    /// Edge segment under the crosshair for map highlight, or the selected play edge.
    func previewEdge(near point: GeoPoint) -> (GeoPoint, GeoPoint)? {
        switch tool {
        case .playArea where boundary.vertices.count >= 3:
            let edge = selectedEdge ?? nearestEdge(in: boundary.vertices, to: point)
            guard let edge, boundary.vertices.count >= 2 else { return nil }
            let start = boundary.vertices[edge]
            let end = boundary.vertices[(edge + 1) % boundary.vertices.count]
            return (start, end)
        case .outOfBounds, .seekerSpawn:
            guard pendingZoneVertices.isEmpty,
                  let id = activeZoneID,
                  let zone = zones.first(where: { $0.id == id }),
                  case let .polygon(polygon) = zone.shape,
                  polygon.vertices.count >= 3 else { return nil }
            let edge = selectedEdge ?? nearestEdge(in: polygon.vertices, to: point)
            guard let edge else { return nil }
            let start = polygon.vertices[edge]
            let end = polygon.vertices[(edge + 1) % polygon.vertices.count]
            return (start, end)
        default:
            return nil
        }
    }

    /// Circle center marker before the radius tap.
    var pendingCircleCenterForMap: GeoPoint? { pendingCircleCenter }

    func preparedForSave() -> PreparedArena {
        var preparedZones: [ArenaZone] = []
        var warnings: [String] = []
        let playReady = boundary.vertices.count >= 3 && !ArenaGeometry.selfIntersects(boundary)
        for zone in zones {
            guard playReady else {
                preparedZones.append(zone)
                continue
            }
            if ArenaGeometry.covers(zone: zone, playArea: boundary) {
                preparedZones.append(zone)
                continue
            }
            if let clipped = ZoneClip.clip(zone, to: boundary) {
                warnings.append("Part of \(zone.name) is outside the play area, so it was clipped to the boundary.")
                preparedZones.append(clipped)
            } else {
                warnings.append("That zone is completely outside the play area, so it was not added.")
            }
        }
        let arena = Arena(
            id: UUID(),
            name: name,
            boundary: boundary,
            zones: preparedZones
        )
        return PreparedArena(arena: arena, blocking: ArenaValidator.issues(in: arena), warnings: warnings)
    }

    func addMapPoint(_ point: GeoPoint) {
        switch tool {
        case .playArea:
            if let index = vertexToMove {
                dragVertex(at: index, to: point)
                return
            }
            if boundary.vertices.count >= 3 {
                _ = insertIntoClosedRing(point, vertices: &boundary.vertices)
                return
            }
            snapshot()
            boundary.vertices.append(point)
        case .safeCircle:
            if let center = pendingCircleCenter {
                snapshot()
                let radius = ArenaGeometry.meters(from: center, to: point)
                var zone = ArenaZone(
                    id: UUID(),
                    name: "Safe zone",
                    kind: .safe,
                    shape: .circle(center: center, radiusMeters: radius)
                )
                if finalizeZone(&zone) {
                    zones.append(zone)
                }
                pendingCircleCenter = nil
            } else {
                snapshot()
                pendingCircleCenter = point
            }
        case .outOfBounds:
            addZonePoint(point, kind: .outOfBounds, defaultName: "Out of bounds")
        case .seekerSpawn:
            addZonePoint(point, kind: .seekerSpawn, defaultName: "Seeker spawn")
        }
    }

    func undo() {
        if let previous = history.popLast() {
            boundary = previous.boundary
            zones = previous.zones
            pendingCircleCenter = previous.pendingCircleCenter
            pendingZoneVertices = previous.pendingZoneVertices
            activeZoneID = previous.activeZoneID
            selectedEdge = previous.selectedEdge
            vertexToMove = previous.vertexToMove
            notice = previous.notice
            return
        }
        if pendingCircleCenter != nil {
            pendingCircleCenter = nil
        }
    }

    private func addZonePoint(_ point: GeoPoint, kind: ZoneKind, defaultName: String) {
        if !pendingZoneVertices.isEmpty {
            if pendingZoneVertices.count < 2 {
                snapshot()
                pendingZoneVertices.append(point)
            } else {
                snapshot()
                let vertices = pendingZoneVertices + [point]
                var zone = ArenaZone(
                    id: UUID(),
                    name: defaultName,
                    kind: kind,
                    shape: .polygon(Polygon(vertices: vertices))
                )
                if finalizeZone(&zone) {
                    zones.append(zone)
                    activeZoneID = zone.id
                }
                pendingZoneVertices = []
            }
            return
        }
        if let id = activeZoneID,
           let index = zones.firstIndex(where: { $0.id == id }),
           zones[index].kind == kind,
           case var .polygon(polygon) = zones[index].shape,
           polygon.vertices.count >= 3
        {
            if insertIntoClosedRing(point, vertices: &polygon.vertices) {
                zones[index].shape = .polygon(polygon)
            }
            return
        }
        snapshot()
        pendingZoneVertices = [point]
        activeZoneID = nil
    }

    /// Clip against the play area when ready. Returns false when the zone is dropped entirely.
    private func finalizeZone(_ zone: inout ArenaZone) -> Bool {
        let playReady = boundary.vertices.count >= 3 && !ArenaGeometry.selfIntersects(boundary)
        guard playReady else { return true }
        if ArenaGeometry.covers(zone: zone, playArea: boundary) { return true }
        if let clipped = ZoneClip.clip(zone, to: boundary) {
            notice = "Part of \(zone.name) is outside the play area, so it was clipped to the boundary."
            zone = clipped
            return true
        }
        notice = "That zone is completely outside the play area, so it was not added."
        return false
    }

    private func insertIntoClosedRing(_ point: GeoPoint, vertices: inout [GeoPoint]) -> Bool {
        let edge = selectedEdge ?? nearestEdge(in: vertices, to: point)
        guard let edge, vertices.count >= 3 else { return false }
        var trial = vertices
        trial.insert(point, at: edge + 1)
        if ArenaGeometry.selfIntersects(Polygon(vertices: trial)) {
            notice = "That point would cross the shape. Drop it nearer the highlighted edge."
            return false
        }
        snapshot()
        vertices = trial
        selectedEdge = nil
        notice = nil
        return true
    }

    private func snapshot() {
        history.append(
            Snapshot(
                boundary: boundary,
                zones: zones,
                pendingCircleCenter: pendingCircleCenter,
                pendingZoneVertices: pendingZoneVertices,
                activeZoneID: activeZoneID,
                selectedEdge: selectedEdge,
                vertexToMove: vertexToMove,
                notice: notice
            )
        )
    }

    /// Local meters, same scale as ArenaGeometry. Not haversine.
    private func nearestEdge(in vertices: [GeoPoint], to point: GeoPoint) -> Int? {
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
        var pendingCircleCenter: GeoPoint?
        var pendingZoneVertices: [GeoPoint]
        var activeZoneID: UUID?
        var selectedEdge: Int?
        var vertexToMove: Int?
        var notice: String?
    }
}

struct PreparedArena {
    var arena: Arena
    var blocking: [ArenaIssue]
    var warnings: [String]
}
