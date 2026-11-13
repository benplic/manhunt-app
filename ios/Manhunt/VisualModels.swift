import CoreLocation
import MapKit
import SwiftUI

/// Sample coordinates and copy for the visual prototype.
/// These types are not the game model. The rules tests in `ManhuntTests` describe
/// the engine that will replace this later.

struct VisualPoint: Hashable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MapReveal: Identifiable, Hashable {
    var id: String
    var name: String
    var colorIndex: Int
    var center: VisualPoint
    var radiusMeters: Double
}

struct VisualZone: Hashable, Identifiable {
    var id: String
    var name: String
    var kind: Kind
    var points: [VisualPoint]
    var radiusMeters: Double?

    enum Kind: String {
        case safe
        case outOfBounds
        case spawn
    }
}

struct VisualArena: Identifiable, Hashable {
    var id: String
    var name: String
    var place: String
    var boundary: [VisualPoint]
    var zones: [VisualZone]
    var boundaryCircle: CircleBoundary? = nil

    var region: MKCoordinateRegion {
        let points = boundary.isEmpty ? [VisualPoint(latitude: 40.6616, longitude: -73.9688)] : boundary
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        let minLat = lats.min() ?? 40.66
        let maxLat = lats.max() ?? 40.67
        let minLon = lons.min() ?? -73.97
        let maxLon = lons.max() ?? -73.96
        let latPad = max((maxLat - minLat) * 1.8, 0.004)
        let lonPad = max((maxLon - minLon) * 1.8, 0.004)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latPad, longitudeDelta: lonPad)
        )
    }
}

enum VisualRole: String, CaseIterable {
    case hider = "Hider"
    case seeker = "Seeker"
    case unassigned = "Open"

    var tint: Color {
        switch self {
        case .hider: HuntColor.hider
        case .seeker: HuntColor.seeker
        case .unassigned: HuntColor.muted
        }
    }
}

struct VisualPlayer: Identifiable, Hashable {
    var id: String
    var name: String
    var role: VisualRole
    var isYou: Bool
    var isHost: Bool
    var point: VisualPoint
    var points: Int
    var earned: Int
}

enum ArenaTool: String, CaseIterable, Identifiable {
    case playArea = "Polygon"
    case playCircle = "Circle"
    case safe = "Safe"
    case outOfBounds = "Out"
    case spawn = "Spawn"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .playArea: "pentagon"
        case .playCircle: "circle.dashed"
        case .safe: "shield"
        case .outOfBounds: "nosign"
        case .spawn: "flag"
        }
    }
}

enum LiveSituation: String, CaseIterable, Identifiable {
    case headStart = "Head start"
    case active = "Live"
    case outOfBounds = "Out of bounds"
    case signalLost = "Signal lost"
    case reconnecting = "Reconnecting"

    var id: String { rawValue }
}

struct VisualModule: Identifiable {
    var id: String
    var title: String
    var blurb: String
    var enabled: Bool
    /// True when the schema has an `enabled` bool. The card toggle writes that field.
    var tracksEnabled: Bool = false
    var locked: Bool = false
    var rows: [VisualRow]
}

struct VisualRow: Identifiable {
    var id: String
    var title: String
    var control: Control
    var number: Double
    var choice: Int
    var flag: Bool

    enum Control {
        case toggle
        case stepper(min: Double, max: Double, step: Double, suffix: String, integer: Bool)
        case options(display: [String], values: [String])
    }

    /// Clamp to the schema bounds so a stepper cannot send a value the server rejects.
    func wireValue() -> RuleValue {
        switch control {
        case .toggle:
            return .bool(flag)
        case let .stepper(min, max, _, _, integer):
            let clamped = Swift.min(max, Swift.max(min, number))
            if integer {
                return .int(Int(clamped.rounded()))
            }
            return .double(clamped)
        case let .options(_, values):
            guard !values.isEmpty else { return .string("") }
            let index = Swift.min(values.count - 1, Swift.max(0, choice))
            return .string(values[index])
        }
    }

    mutating func apply(_ value: RuleValue) {
        switch (control, value) {
        case (.toggle, let .bool(flag)):
            self.flag = flag
        case let (.stepper(min, max, _, _, _), .int(number)):
            self.number = Swift.min(max, Swift.max(min, Double(number)))
        case let (.stepper(min, max, _, _, _), .double(number)):
            self.number = Swift.min(max, Swift.max(min, number))
        case let (.options(_, values), .string(raw)):
            if let index = values.firstIndex(of: raw) {
                choice = index
            }
        default:
            break
        }
    }

    /// Keep picker and stepper values inside the control so SwiftUI does not trap.
    mutating func clampToControl() {
        switch control {
        case let .options(_, values):
            if values.isEmpty {
                choice = 0
            } else {
                choice = min(values.count - 1, max(0, choice))
            }
        case let .stepper(min, max, _, _, _):
            guard min <= max else { return }
            number = Swift.min(max, Swift.max(min, number))
        case .toggle:
            break
        }
    }

    var stepperRangeIsUsable: Bool {
        guard case let .stepper(min, max, step, _, _) = control else { return false }
        return min <= max && step > 0
    }
}

struct PowerChip: Identifiable {
    var id: String
    var title: String
    var detail: String
    var cost: Int
    var role: VisualRole
}

enum SamplePark {
    static let arenas: [VisualArena] = [riverside, schoolyard]

    static let riverside = VisualArena(
        id: "riverside",
        name: "Riverside Green",
        place: "Prospect Park",
        boundary: [
            VisualPoint(latitude: 40.66355, longitude: -73.96995),
            VisualPoint(latitude: 40.66320, longitude: -73.96785),
            VisualPoint(latitude: 40.66155, longitude: -73.96735),
            VisualPoint(latitude: 40.66025, longitude: -73.96835),
            VisualPoint(latitude: 40.66015, longitude: -73.97015),
            VisualPoint(latitude: 40.66185, longitude: -73.97075),
        ],
        zones: [
            VisualZone(
                id: "gazebo",
                name: "Gazebo",
                kind: .safe,
                points: [VisualPoint(latitude: 40.66215, longitude: -73.96915)],
                radiusMeters: 42
            ),
            VisualZone(
                id: "pond",
                name: "Pond edge",
                kind: .outOfBounds,
                points: [
                    VisualPoint(latitude: 40.66105, longitude: -73.96805),
                    VisualPoint(latitude: 40.66070, longitude: -73.96770),
                    VisualPoint(latitude: 40.66055, longitude: -73.96825),
                ],
                radiusMeters: nil
            ),
            VisualZone(
                id: "gate",
                name: "South gate",
                kind: .spawn,
                points: [
                    VisualPoint(latitude: 40.66055, longitude: -73.96970),
                    VisualPoint(latitude: 40.66040, longitude: -73.96910),
                    VisualPoint(latitude: 40.66085, longitude: -73.96895),
                    VisualPoint(latitude: 40.66100, longitude: -73.96955),
                ],
                radiusMeters: nil
            ),
        ]
    )

    static let schoolyard = VisualArena(
        id: "schoolyard",
        name: "Schoolyard",
        place: "Park Slope",
        boundary: [
            VisualPoint(latitude: 40.67240, longitude: -73.97720),
            VisualPoint(latitude: 40.67235, longitude: -73.97540),
            VisualPoint(latitude: 40.67090, longitude: -73.97530),
            VisualPoint(latitude: 40.67085, longitude: -73.97710),
        ],
        zones: [
            VisualZone(
                id: "yard-safe",
                name: "Play structure",
                kind: .safe,
                points: [VisualPoint(latitude: 40.67170, longitude: -73.97620)],
                radiusMeters: 28
            ),
        ]
    )

    static let players: [VisualPlayer] = [
        VisualPlayer(id: "casey", name: "Casey Lee", role: .seeker, isYou: true, isHost: true, point: VisualPoint(latitude: 40.66070, longitude: -73.96940), points: 120, earned: 120),
        VisualPlayer(id: "riley", name: "Riley Chen", role: .hider, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66240, longitude: -73.96840), points: 85, earned: 85),
        VisualPlayer(id: "jordan", name: "Jordan Blake", role: .seeker, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66110, longitude: -73.97010), points: 60, earned: 60),
        VisualPlayer(id: "quinn", name: "Quinn Adler", role: .hider, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66290, longitude: -73.96960), points: 40, earned: 40),
        VisualPlayer(id: "sam", name: "Sam Patel", role: .hider, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66140, longitude: -73.96790), points: 55, earned: 55),
    ]

    static let powerUps: [PowerChip] = [
        PowerChip(id: "ghost", title: "Ghost", detail: "Skip the next reveal", cost: 20, role: .hider),
        PowerChip(id: "decoy", title: "Decoy", detail: "Next pin is a fake", cost: 40, role: .hider),
        PowerChip(id: "radar", title: "Radar", detail: "See seekers for 20s", cost: 40, role: .hider),
        PowerChip(id: "jammer", title: "Jammer", detail: "Mute hot / cold hints", cost: 55, role: .hider),
        PowerChip(id: "shield", title: "Shield", detail: "Untaggable for 30s", cost: 70, role: .hider),
        PowerChip(id: "scan", title: "Scan", detail: "Reveal one hider now", cost: 25, role: .seeker),
        PowerChip(id: "tracker", title: "Tracker", detail: "Hot / cold for 3 min", cost: 50, role: .seeker),
        PowerChip(id: "lockdown", title: "Lockdown", detail: "Safe zones off", cost: 75, role: .seeker),
    ]

    static func classicModules() -> [VisualModule] {
        ModuleForm.offlineModules()
    }
}

