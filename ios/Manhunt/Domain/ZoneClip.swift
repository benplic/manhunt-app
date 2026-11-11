import Foundation

/// Clips zones to the play boundary for editor preview and save. Uses flat meters at play latitude.
/// Convex play areas use Sutherland–Hodgman. Concave ones are split into ears first, because
/// half-plane clipping is wrong when the play polygon has a dent. Ear pieces are unioned so a
/// zone that covers several ears keeps the whole interior, not only the largest triangle.
enum ZoneClip {
  /// Largest overlap of `zone` with `play`. Nil when the overlap is empty.
  /// A circle fully inside `play` is returned unchanged.
  static func clip(_ zone: ArenaZone, to play: Polygon) -> ArenaZone? {
    guard play.vertices.count >= 3 else { return zone }
    switch zone.shape {
    case let .circle(center, radius):
      if ArenaGeometry.contains(center, in: play),
         ArenaGeometry.covers(zone: zone, playArea: play)
      {
        return zone
      }
      let ring = circleSamples(center: center, radiusMeters: radius, steps: 32)
      guard let clipped = clipPolygon(ring, play: play.vertices), clipped.count >= 3 else { return nil }
      return ArenaZone(
        id: zone.id,
        name: zone.name,
        kind: zone.kind,
        shape: .polygon(Polygon(vertices: clipped))
      )
    case let .polygon(polygon):
      if polygon.vertices.count < 3 { return nil }
      if ArenaGeometry.covers(zone: zone, playArea: play) { return zone }
      guard let clipped = clipPolygon(polygon.vertices, play: play.vertices) else { return nil }
      return ArenaZone(
        id: zone.id,
        name: zone.name,
        kind: zone.kind,
        shape: .polygon(Polygon(vertices: clipped))
      )
    }
  }

  static func clipPolygon(_ subject: [GeoPoint], play: [GeoPoint]) -> [GeoPoint]? {
    guard subject.count >= 3, play.count >= 3 else { return nil }
    let origin = play[0]
    let subjectXY = ensureCCW(subject.map { localXY($0, origin: origin) })
    let playXY = ensureCCW(play.map { localXY($0, origin: origin) })
    // A clockwise ring has its interior on the right. Sutherland–Hodgman keeps the left side,
    // so an unflipped ring reports a real overlap as completely outside.
    let pieces = isConvex(playXY) ? [playXY] : earClip(playXY)
    guard !pieces.isEmpty else { return nil }
    var fragments: [[XY]] = []
    for piece in pieces {
      guard let clipped = clipConvex(subjectXY, clip: piece) else { continue }
      fragments.append(clipped)
    }
    // Shared ear edges cancel. What remains is the outline of the overlap.
    // A zone that crosses a bay can leave two polygons; keep the largest, and
    // drop a sliver under 1 m². Same rule as the server's shapely clip.
    guard let merged = unionFragments(fragments),
          merged.count >= 3,
          polygonAreaMeters(merged) >= 1
    else { return nil }
    return merged.map { geoFromLocal($0, origin: origin) }
  }

  /// Glue ear clippings into one ring by cancelling edges that bound two pieces.
  private static func unionFragments(_ fragments: [[XY]]) -> [XY]? {
    var edges: [DirectedEdge] = []
    for fragment in fragments {
      let ring = dropDuplicateNeighbors(fragment)
      guard ring.count >= 3, polygonAreaMeters(ring) > 1e-6 else { continue }
      for index in ring.indices {
        edges.append(DirectedEdge(start: ring[index], end: ring[(index + 1) % ring.count]))
      }
    }
    guard !edges.isEmpty else { return nil }
    let split = splitEdges(edges)
    var counts: [EdgeKey: Int] = [:]
    var sample: [EdgeKey: DirectedEdge] = [:]
    for edge in split {
      let start = quantize(edge.start)
      let end = quantize(edge.end)
      if start == end { continue }
      let key = EdgeKey(start: start, end: end)
      counts[key, default: 0] += 1
      sample[key] = edge
    }
    var outgoing: [QuantPoint: [QuantPoint]] = [:]
    for (key, count) in counts {
      let reverse = EdgeKey(start: key.end, end: key.start)
      let net = count - (counts[reverse] ?? 0)
      guard net > 0 else { continue }
      for _ in 0..<net {
        outgoing[key.start, default: []].append(key.end)
      }
    }
    var rings: [[XY]] = []
    var safety = split.count + 2
    while safety > 0, let start = outgoing.first(where: { !$0.value.isEmpty })?.key {
      safety -= 1
      var ring: [XY] = []
      var current = start
      var steps = split.count + 2
      while steps > 0 {
        steps -= 1
        guard var nexts = outgoing[current], !nexts.isEmpty else { break }
        let next = nexts.removeFirst()
        outgoing[current] = nexts
        if let edge = sample[EdgeKey(start: current, end: next)] {
          ring.append(edge.start)
        }
        current = next
        if current == start { break }
      }
      let cleaned = dropDuplicateNeighbors(ring)
      if cleaned.count >= 3, current == start {
        rings.append(cleaned)
      }
    }
    guard let best = rings.max(by: { polygonAreaMeters($0) < polygonAreaMeters($1) }) else { return nil }
    return best
  }

  /// Break edges at vertices that lie on them so a T-junction cancels in pieces, not as one long edge.
  private static func splitEdges(_ edges: [DirectedEdge]) -> [DirectedEdge] {
    var canon: [XY] = []
    for edge in edges {
      for point in [edge.start, edge.end] {
        if !canon.contains(where: { distance($0, point) <= 0.0001 }) {
          canon.append(point)
        }
      }
    }
    func snap(_ point: XY) -> XY {
      canon.first { distance($0, point) <= 0.0001 } ?? point
    }
    var split: [DirectedEdge] = []
    for edge in edges {
      let start = snap(edge.start)
      let end = snap(edge.end)
      var hits: [(Double, XY)] = []
      for point in canon {
        let (gap, t) = parameterAlong(point, from: start, to: end)
        if gap <= 0.0001, t > 0.0001, t < 0.9999 {
          hits.append((t, snap(point)))
        }
      }
      hits.sort { $0.0 < $1.0 }
      var chain = [start]
      chain.append(contentsOf: hits.map(\.1))
      chain.append(end)
      for index in 0..<(chain.count - 1) where distance(chain[index], chain[index + 1]) > 0.0001 {
        split.append(DirectedEdge(start: chain[index], end: chain[index + 1]))
      }
    }
    return split
  }

  private static func dropDuplicateNeighbors(_ vertices: [XY]) -> [XY] {
    var ring: [XY] = []
    for point in vertices {
      if let last = ring.last, distance(last, point) <= 0.0001 { continue }
      ring.append(point)
    }
    if ring.count >= 2, let first = ring.first, let last = ring.last, distance(first, last) <= 0.0001 {
      ring.removeLast()
    }
    return ring
  }

  private static func distance(_ a: XY, _ b: XY) -> Double {
    hypot(a.x - b.x, a.y - b.y)
  }

  /// Distance to the segment, and the unclamped parameter along start→end.
  private static func parameterAlong(_ point: XY, from start: XY, to end: XY) -> (Double, Double) {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    if lengthSquared < 1e-18 {
      return (distance(point, start), 0)
    }
    let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    let clamped = min(1, max(0, t))
    let projected = XY(x: start.x + dx * clamped, y: start.y + dy * clamped)
    return (distance(point, projected), t)
  }

  private struct DirectedEdge {
    var start: XY
    var end: XY
  }

  private struct QuantPoint: Hashable {
    var x: Int
    var y: Int
  }

  private struct EdgeKey: Hashable {
    var start: QuantPoint
    var end: QuantPoint
  }

  private static func quantize(_ point: XY) -> QuantPoint {
    QuantPoint(
      x: Int((point.x / 0.0001).rounded()),
      y: Int((point.y / 0.0001).rounded())
    )
  }

  private static func clipConvex(_ subject: [XY], clip: [XY]) -> [XY]? {
    var output = subject
    for index in clip.indices {
      let start = clip[index]
      let end = clip[(index + 1) % clip.count]
      output = clipAgainstEdge(output, start: start, end: end)
      if output.isEmpty { return nil }
    }
    return output.count >= 3 ? output : nil
  }

  private static func ensureCCW(_ vertices: [XY]) -> [XY] {
    signedArea(vertices) < 0 ? Array(vertices.reversed()) : vertices
  }

  private static func isConvex(_ vertices: [XY]) -> Bool {
    guard vertices.count >= 3 else { return false }
    for index in vertices.indices {
      let previous = vertices[(index + vertices.count - 1) % vertices.count]
      let current = vertices[index]
      let next = vertices[(index + 1) % vertices.count]
      if cross(previous, current, next) < -1e-8 { return false }
    }
    return true
  }

  /// Triangles that cover a simple concave polygon. Empty when the ring is not a simple ear clip.
  private static func earClip(_ polygon: [XY]) -> [[XY]] {
    var ring = polygon
    var triangles: [[XY]] = []
    var safety = ring.count * ring.count
    while ring.count > 3 && safety > 0 {
      safety -= 1
      var found = false
      for index in ring.indices {
        let previousIndex = (index + ring.count - 1) % ring.count
        let nextIndex = (index + 1) % ring.count
        let previous = ring[previousIndex]
        let current = ring[index]
        let next = ring[nextIndex]
        if cross(previous, current, next) <= 1e-8 { continue }
        if earContainsVertex(ring, skip: [previousIndex, index, nextIndex], a: previous, b: current, c: next) {
          continue
        }
        triangles.append([previous, current, next])
        ring.remove(at: index)
        found = true
        break
      }
      if !found { return [] }
    }
    if ring.count == 3, cross(ring[0], ring[1], ring[2]) > 1e-8 {
      triangles.append(ring)
    }
    return triangles
  }

  private static func earContainsVertex(_ ring: [XY], skip: [Int], a: XY, b: XY, c: XY) -> Bool {
    for (index, point) in ring.enumerated() where !skip.contains(index) {
      if pointInTriangle(point, a, b, c) { return true }
    }
    return false
  }

  /// Strict interior. Points on an edge are not inside, so a neighbor on the diagonal is not a blocker.
  private static func pointInTriangle(_ point: XY, _ a: XY, _ b: XY, _ c: XY) -> Bool {
    let ab = cross(a, b, point)
    let bc = cross(b, c, point)
    let ca = cross(c, a, point)
    let hasNegative = ab < -1e-9 || bc < -1e-9 || ca < -1e-9
    let hasPositive = ab > 1e-9 || bc > 1e-9 || ca > 1e-9
    return !(hasNegative && hasPositive) && abs(ab) > 1e-9 && abs(bc) > 1e-9 && abs(ca) > 1e-9
  }

  private static func cross(_ a: XY, _ b: XY, _ c: XY) -> Double {
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  }

  private static func signedArea(_ vertices: [XY]) -> Double {
    var area = 0.0
    for index in vertices.indices {
      let next = (index + 1) % vertices.count
      area += vertices[index].x * vertices[next].y - vertices[next].x * vertices[index].y
    }
    return area / 2
  }

  private static func circleSamples(center: GeoPoint, radiusMeters: Double, steps: Int) -> [GeoPoint] {
    (0..<steps).map { index in
      let angle = Double(index) / Double(steps) * 2 * .pi
      let north = radiusMeters * cos(angle)
      let east = radiusMeters * sin(angle)
      return offsetMeters(from: center, northMeters: north, eastMeters: east)
    }
  }

  private static func offsetMeters(from origin: GeoPoint, northMeters: Double, eastMeters: Double) -> GeoPoint {
    let lat0 = origin.latitude * .pi / 180
    let dLat = northMeters / ArenaGeometry.metersPerDegree
    let dLon = eastMeters / (ArenaGeometry.metersPerDegree * cos(lat0))
    return GeoPoint(latitude: origin.latitude + dLat, longitude: origin.longitude + dLon)
  }

  private struct XY {
    var x: Double
    var y: Double
  }

  private static func localXY(_ point: GeoPoint, origin: GeoPoint) -> XY {
    let scale = cos(origin.latitude * .pi / 180)
    return XY(
      x: (point.longitude - origin.longitude) * ArenaGeometry.metersPerDegree * scale,
      y: (point.latitude - origin.latitude) * ArenaGeometry.metersPerDegree
    )
  }

  private static func geoFromLocal(_ point: XY, origin: GeoPoint) -> GeoPoint {
    let scale = cos(origin.latitude * .pi / 180)
    return GeoPoint(
      latitude: origin.latitude + point.y / ArenaGeometry.metersPerDegree,
      longitude: origin.longitude + point.x / (ArenaGeometry.metersPerDegree * scale)
    )
  }

  /// Sutherland–Hodgman against a convex clip edge (interior to the left of start→end).
  private static func clipAgainstEdge(_ input: [XY], start: XY, end: XY) -> [XY] {
    guard !input.isEmpty else { return [] }
    var output: [XY] = []
    var previous = input.last!
    var previousInside = inside(start: start, end: end, point: previous)
    for current in input {
      let currentInside = inside(start: start, end: end, point: current)
      if currentInside {
        if !previousInside, let hit = intersection(start: start, end: end, a: previous, b: current) {
          output.append(hit)
        }
        output.append(current)
      } else if previousInside, let hit = intersection(start: start, end: end, a: previous, b: current) {
        output.append(hit)
      }
      previous = current
      previousInside = currentInside
    }
    return output
  }

  private static func inside(start: XY, end: XY, point: XY) -> Bool {
    (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x) >= 0
  }

  private static func intersection(start: XY, end: XY, a: XY, b: XY) -> XY? {
    let x1 = start.x
    let y1 = start.y
    let x2 = end.x
    let y2 = end.y
    let x3 = a.x
    let y3 = a.y
    let x4 = b.x
    let y4 = b.y
    let denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(denominator) < 1e-12 { return nil }
    let px = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / denominator
    let py = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / denominator
    return XY(x: px, y: py)
  }

  private static func polygonAreaMeters(_ vertices: [XY]) -> Double {
    guard vertices.count >= 3 else { return 0 }
    var area = 0.0
    for index in vertices.indices {
      let next = (index + 1) % vertices.count
      area += vertices[index].x * vertices[next].y - vertices[next].x * vertices[index].y
    }
    return abs(area) / 2
  }
}
