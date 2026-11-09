import Foundation
@testable import Manhunt

enum Fixtures {
    /// Local flat projection at the equator so 1 meter is 1/111320 of a degree.
    static func meters(x: Double, y: Double) -> GeoPoint {
        GeoPoint(latitude: y / 111_320, longitude: x / 111_320)
    }

    static func square() -> Arena {
        Arena(
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
}
