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
}

enum ArenaTool: String, CaseIterable, Identifiable {
    case playArea = "Play area"
    case safe = "Safe"
    case outOfBounds = "Out"
    case spawn = "Spawn"

    var id: String { rawValue }
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
        case stepper(min: Double, max: Double, step: Double, suffix: String)
        case options([String])
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
        VisualPlayer(id: "casey", name: "Casey Lee", role: .seeker, isYou: true, isHost: true, point: VisualPoint(latitude: 40.66070, longitude: -73.96940), points: 120),
        VisualPlayer(id: "riley", name: "Riley Chen", role: .hider, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66240, longitude: -73.96840), points: 85),
        VisualPlayer(id: "jordan", name: "Jordan Blake", role: .seeker, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66110, longitude: -73.97010), points: 60),
        VisualPlayer(id: "quinn", name: "Quinn Adler", role: .hider, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66290, longitude: -73.96960), points: 40),
        VisualPlayer(id: "sam", name: "Sam Patel", role: .hider, isYou: false, isHost: false, point: VisualPoint(latitude: 40.66140, longitude: -73.96790), points: 55),
    ]

    static let powerUps: [PowerChip] = [
        PowerChip(id: "ghost", title: "Ghost", detail: "Skip the next reveal", cost: 40, role: .hider),
        PowerChip(id: "decoy", title: "Decoy", detail: "Next pin is a fake", cost: 60, role: .hider),
        PowerChip(id: "radar", title: "Radar", detail: "See seekers for 20s", cost: 50, role: .hider),
        PowerChip(id: "jammer", title: "Jammer", detail: "Mute hot / cold hints", cost: 70, role: .hider),
        PowerChip(id: "shield", title: "Shield", detail: "Untaggable for 30s", cost: 80, role: .hider),
        PowerChip(id: "scan", title: "Scan", detail: "Reveal one hider now", cost: 45, role: .seeker),
        PowerChip(id: "tracker", title: "Tracker", detail: "Hot / cold for 3 min", cost: 55, role: .seeker),
        PowerChip(id: "lockdown", title: "Lockdown", detail: "Safe zones off", cost: 90, role: .seeker),
    ]

    static func classicModules() -> [VisualModule] {
        [
            VisualModule(
                id: "roles",
                title: "Roles",
                blurb: "How hiders and seekers are chosen in the lobby.",
                enabled: true,
                rows: [
                    VisualRow(id: "mode", title: "Assignment", control: .options(["Random", "Manual", "Volunteer"]), number: 0, choice: 0, flag: true),
                    VisualRow(id: "hiders", title: "Hiders", control: .stepper(min: 1, max: 10, step: 1, suffix: ""), number: 3, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "head_start",
                title: "Head start",
                blurb: "Hiders hide before seekers are released.",
                enabled: true,
                rows: [
                    VisualRow(id: "duration", title: "Duration", control: .stepper(min: 15, max: 300, step: 15, suffix: "s"), number: 45, choice: 0, flag: true),
                    VisualRow(id: "lock", title: "Seekers wait", control: .options(["Locked map", "Spawn zone"]), number: 0, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "reveal",
                title: "Fuzzy reveal",
                blurb: "Seekers see approximate hider pins on a timer.",
                enabled: true,
                rows: [
                    VisualRow(id: "interval", title: "Every", control: .stepper(min: 20, max: 180, step: 10, suffix: "s"), number: 60, choice: 0, flag: true),
                    VisualRow(id: "show", title: "Pin stays", control: .stepper(min: 5, max: 30, step: 5, suffix: "s"), number: 10, choice: 0, flag: true),
                    VisualRow(id: "fuzz", title: "Fuzz", control: .stepper(min: 10, max: 80, step: 5, suffix: "m"), number: 30, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "hot_cold",
                title: "Hot / cold",
                blurb: "Distance and direction toward hiders. Not a precise pin.",
                enabled: true,
                rows: [
                    VisualRow(id: "on", title: "Hints", control: .toggle, number: 0, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "tag",
                title: "Tag",
                blurb: "Ultra Wideband confirms the tag. A rotating code is the fallback.",
                enabled: true,
                rows: [
                    VisualRow(id: "radius", title: "Radius", control: .stepper(min: 1, max: 5, step: 0.5, suffix: "m"), number: 2, choice: 0, flag: true),
                    VisualRow(id: "result", title: "Result", control: .options(["Eliminate", "Join seekers"]), number: 0, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "zones",
                title: "Zones",
                blurb: "Out of bounds counts down. Safe zones block tags until time runs out.",
                enabled: true,
                rows: [
                    VisualRow(id: "countdown", title: "Out of bounds", control: .stepper(min: 5, max: 60, step: 5, suffix: "s"), number: 15, choice: 0, flag: true),
                    VisualRow(id: "penalty", title: "Penalty", control: .options(["Auto-tag", "Forced reveal"]), number: 0, choice: 0, flag: true),
                    VisualRow(id: "safe_time", title: "Safe visit", control: .stepper(min: 15, max: 180, step: 15, suffix: "s"), number: 45, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "signal",
                title: "Going dark",
                blurb: "Silence shares the last precise location with everyone. Safety overrides the game.",
                enabled: true,
                rows: [
                    VisualRow(id: "silence", title: "Call it dark after", control: .stepper(min: 15, max: 120, step: 15, suffix: "s"), number: 30, choice: 0, flag: true),
                ]
            ),
            VisualModule(
                id: "win",
                title: "Win",
                blurb: "How the hunt ends.",
                enabled: true,
                rows: [
                    VisualRow(id: "condition", title: "Ends when", control: .options(["All hiders caught", "Time limit", "Either"]), number: 0, choice: 2, flag: true),
                    VisualRow(id: "limit", title: "Time limit", control: .stepper(min: 10, max: 90, step: 5, suffix: "min"), number: 30, choice: 0, flag: true),
                ]
            ),
        ]
    }
}

