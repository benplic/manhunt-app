import Foundation

struct UserDTO: Codable, Hashable {
    var id: UUID
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct AuthOut: Codable {
    var accessToken: String
    var expiresAt: String
    var user: UserDTO
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
        case user
        case refreshToken = "refresh_token"
    }
}

struct APIIssue: Codable, Equatable {
    var code: String
    var name: String?
}

struct APIErrorBody: Codable {
    var error: Payload

    struct Payload: Codable {
        var code: ErrorCode
        var message: String
        var issues: [APIIssue]

        enum CodingKeys: String, CodingKey {
            case code, message, details
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(ErrorCode.self, forKey: .code)
            message = try container.decode(String.self, forKey: .message)
            // details is sometimes {issues: [...]}, sometimes {field: "..."}.
            // A mismatch must not throw away the message.
            if let details = try? container.decode(Details.self, forKey: .details) {
                issues = details.issues
            } else {
                issues = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }

    private struct Details: Decodable {
        var issues: [APIIssue]

        enum CodingKeys: String, CodingKey { case issues }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let objects = try? container.decode([APIIssue].self, forKey: .issues) {
                issues = objects
            } else if let codes = try? container.decode([String].self, forKey: .issues) {
                issues = codes.map { APIIssue(code: $0, name: nil) }
            } else {
                issues = []
            }
        }
    }
}

struct ZoneTimerDTO: Codable, Equatable {
    var radiusM: Double
    var nextRadiusM: Double?
    var shrinksInS: Int?

    enum CodingKeys: String, CodingKey {
        case radiusM = "radius_m"
        case nextRadiusM = "next_radius_m"
        case shrinksInS = "shrinks_in_s"
    }
}

struct PowerUpDTO: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var cost: Int
    var role: PlayerRole

    enum CodingKeys: String, CodingKey {
        case id, title, cost, role
    }
}

struct TimersDTO: Codable, Equatable {
    var headStartS: Int
    var timeLimitS: Int
    var revealIntervalS: Int?
    var nextRevealInS: Int?
    var zone: ZoneTimerDTO?

    enum CodingKeys: String, CodingKey {
        case headStartS = "head_start_s"
        case timeLimitS = "time_limit_s"
        case revealIntervalS = "reveal_interval_s"
        case nextRevealInS = "next_reveal_in_s"
        case zone
    }
}

struct PlayerViewDTO: Codable {
    var gameId: UUID
    var joinCode: String
    var phase: MatchPhase
    var phaseRemainingS: Int?
    var gameElapsedS: Int
    var timeLimitRemainingS: Int?
    var timers: TimersDTO? = nil
    var you: YouDTO
    var players: [PlayerDTO]
    var reveals: [RevealDTO]
    var banners: [BannerDTO]
    var result: ResultDTO?
    var tagMethod: String? = nil
    var seekerLock: String? = nil
    var spawnLock: SpawnLockDTO? = nil
    /// Seconds until a sample lobby starts. Nil for a normal game.
    var lobbyStartsInS: Int? = nil
    /// Play area for this game. Every phone draws this, not its local selection.
    var arena: Arena? = nil
    /// Demo lobby state and bot summary. Nil for normal games.
    var demo: DemoDTO? = nil
    /// Dock chips for the viewer. Nil on older servers (use SamplePark fallback).
    var powerUps: [PowerUpDTO]? = nil

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case joinCode = "join_code"
        case phase
        case phaseRemainingS = "phase_remaining_s"
        case gameElapsedS = "game_elapsed_s"
        case timeLimitRemainingS = "time_limit_remaining_s"
        case timers
        case tagMethod = "tag_method"
        case seekerLock = "seeker_lock"
        case spawnLock = "spawn_lock"
        case you, players, reveals, banners, result
        case lobbyStartsInS = "lobby_starts_in_s"
        case arena
        case demo
        case powerUps = "power_ups"
    }
}

struct DemoBotDTO: Codable, Equatable, Identifiable {
    var playerId: UUID
    var displayName: String
    var role: PlayerRole
    var status: PlayerStatus
    var mode: String

    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case displayName = "display_name"
        case role, status, mode
    }
}

struct DemoPointDTO: Codable, Equatable {
    var lat: Double
    var lon: Double
}

struct DemoDTO: Codable, Equatable {
    var speed: Int
    var lobbyHold: Bool
    var seekerLock: String
    var controlsEnabled: Bool
    var virtualLocation: DemoPointDTO?
    var bots: [DemoBotDTO]

    enum CodingKeys: String, CodingKey {
        case speed
        case lobbyHold = "lobby_hold"
        case seekerLock = "seeker_lock"
        case controlsEnabled = "controls_enabled"
        case virtualLocation = "virtual_location"
        case bots
    }
}

struct YouDTO: Codable {
    var playerId: UUID
    var role: PlayerRole
    var status: PlayerStatus
    var isHost: Bool
    var bounds: BoundsDTO
    var safeZone: SafeDTO?
    var points: Int
    /// Lifetime earned score; nil on older servers decodes as absent.
    var pointsEarned: Int? = nil
    var hint: HintDTO? = nil
    var effects: [String]? = nil
    var cooldowns: [String: Int]? = nil
    /// Seconds until this hider may taunt again. Nil on older servers.
    var tauntCooldownS: Int? = nil
    /// Host turned taunts off; nil on older servers decodes as absent (show button).
    var tauntEnabled: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case role, status
        case isHost = "is_host"
        case bounds
        case safeZone = "safe_zone"
        case points
        case pointsEarned = "points_earned"
        case hint, effects, cooldowns
        case tauntCooldownS = "taunt_cooldown_s"
        case tauntEnabled = "taunt_enabled"
    }
}

struct HintDTO: Codable, Equatable {
    var band: String?
    var meters: Int?
    var name: String?
    var bearingDeg: Int?

    enum CodingKeys: String, CodingKey {
        case band, meters, name
        case bearingDeg = "bearing_deg"
    }
}

struct SpawnLockDTO: Codable, Equatable {
    var outside: Bool
    var zones: [ArenaZone]
    /// True while the head-start countdown is waiting for every seeker to be in spawn.
    var holding: Bool

    enum CodingKeys: String, CodingKey {
        case outside
        case zones
        case holding
    }

    init(outside: Bool, zones: [ArenaZone], holding: Bool = false) {
        self.outside = outside
        self.zones = zones
        self.holding = holding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outside = try container.decode(Bool.self, forKey: .outside)
        zones = try container.decode([ArenaZone].self, forKey: .zones)
        // Older views omit the flag. Missing means the countdown is running.
        holding = try container.decodeIfPresent(Bool.self, forKey: .holding) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outside, forKey: .outside)
        try container.encode(zones, forKey: .zones)
        try container.encode(holding, forKey: .holding)
    }
}

struct BoundsDTO: Codable {
    var phase: String
    var remainingS: Int?

    enum CodingKeys: String, CodingKey {
        case phase
        case remainingS = "remaining_s"
    }
}

struct SafeDTO: Codable {
    var zoneId: UUID
    var remainingS: Int?

    enum CodingKeys: String, CodingKey {
        case zoneId = "zone_id"
        case remainingS = "remaining_s"
    }
}

struct PlayerDTO: Codable, Identifiable, Hashable {
    var playerId: UUID
    var displayName: String
    var role: PlayerRole
    var status: PlayerStatus
    var isHost: Bool
    var points: Int? = nil
    var pointsEarned: Int? = nil
    var location: LocationDTO?

    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case displayName = "display_name"
        case role, status
        case isHost = "is_host"
        case points
        case pointsEarned = "points_earned"
        case location
    }
}

struct LocationDTO: Codable, Hashable {
    var lat: Double
    var lon: Double
    var accuracyM: Double
    var at: String
    var kind: String

    enum CodingKeys: String, CodingKey {
        case lat, lon, at, kind
        case accuracyM = "accuracy_m"
    }
}

struct RevealDTO: Codable, Identifiable {
    var revealId: UUID
    var playerId: UUID
    var lat: Double
    var lon: Double
    var radiusM: Double
    var expiresInS: Int
    var id: UUID { revealId }

    enum CodingKeys: String, CodingKey {
        case revealId = "reveal_id"
        case playerId = "player_id"
        case lat, lon
        case radiusM = "radius_m"
        case expiresInS = "expires_in_s"
    }
}

struct BannerDTO: Codable, Identifiable {
    var bannerId: UUID
    var tone: String
    var title: String
    var detail: String
    var playerId: UUID?
    var id: UUID { bannerId }

    enum CodingKeys: String, CodingKey {
        case bannerId = "banner_id"
        case tone, title, detail
        case playerId = "player_id"
    }
}

struct ResultDTO: Codable {
    var winner: String
    var reason: String
    var endedAt: String?

    enum CodingKeys: String, CodingKey {
        case winner, reason
        case endedAt = "ended_at"
    }
}

struct TimelineEventDTO: Codable, Identifiable, Hashable {
    var seq: Int
    var type: String
    var payload: TimelinePayloadDTO
    var id: Int { seq }
}

struct TimelinePayloadDTO: Codable, Hashable {
    var text: String?
    var tone: String?
}

struct TimelineOut: Codable {
    var events: [TimelineEventDTO]
}

struct ServiceError: Error, Equatable {
    var code: ErrorCode
    var message: String
    var issues: [APIIssue] = []
}
