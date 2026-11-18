import Foundation

enum MatchPhase: String, Codable, Equatable {
    case lobby
    case headStart = "head_start"
    case active
    case paused
    case ended
}

enum PlayerStatus: String, Codable, Equatable {
    case active
    case eliminated
    case signalLost = "signal_lost"
}

enum PurchaseDenial: Equatable {
    case insufficientPoints
    case coolingDown
    case wrongPhase
    case wrongRole
    case eliminated
    case needsTarget
    case targetOutside
    /// Power-up is listed but the current reveal mode forbids it (e.g. Tracker).
    case unavailable
}

enum PurchaseDecision: Equatable {
    case allowed
    case denied(PurchaseDenial)
}

struct PurchaseRequest {
    var balance: Int
    var cost: Int
    var cooldownRemaining: Int
    var phase: MatchPhase
    var role: PlayerRole
    var requiredRole: PlayerRole
    var status: PlayerStatus
    var requiresTarget: Bool
    var hasTarget: Bool
    /// Set false when a decoy point was picked but sits outside the play area.
    var targetInsidePlayArea: Bool = true
    /// Server or local rules marked this power unavailable for the current mode.
    var available: Bool = true
}

enum PowerUpRules {
    /// Map / player / zone targets the dock must collect before POST.
    static func requiresTarget(powerID: String) -> Bool {
        switch powerID {
        case "decoy", "create_safe", "move_safe", "rescue":
            return true
        default:
            return false
        }
    }

    /// Point-in-play-area check (decoy / create_safe / move_safe). Rescue uses a player id.
    static func requiresMapPoint(powerID: String) -> Bool {
        switch powerID {
        case "decoy", "create_safe", "move_safe":
            return true
        default:
            return false
        }
    }

    static func decide(_ request: PurchaseRequest) -> PurchaseDecision {
        if request.balance < request.cost { return .denied(.insufficientPoints) }
        if request.cooldownRemaining > 0 { return .denied(.coolingDown) }
        if request.phase != .active { return .denied(.wrongPhase) }
        if request.role != request.requiredRole { return .denied(.wrongRole) }
        if request.status == .eliminated { return .denied(.eliminated) }
        if !request.available { return .denied(.unavailable) }
        if request.requiresTarget && !request.hasTarget { return .denied(.needsTarget) }
        if request.requiresTarget && request.hasTarget && !request.targetInsidePlayArea {
            return .denied(.targetOutside)
        }
        return .allowed
    }

    /// Decoy is tappable when every rule passes except picking a map target.
    /// Unavailable powers stay greyed but may still receive a tap to show denial copy.
    static func chipIsTappable(_ request: PurchaseRequest) -> Bool {
        switch decide(request) {
        case .allowed:
            return true
        case .denied(.needsTarget):
            var probe = request
            probe.hasTarget = true
            return decide(probe) == .allowed
        default:
            return false
        }
    }

    /// Greyed chips that should still accept a tap to explain why.
    static func chipShowsDenialOnTap(_ request: PurchaseRequest) -> Bool {
        if case .denied(.unavailable) = decide(request) { return true }
        return false
    }
}

/// Tracker is timed hot/cold. Forbid when Hot/cold mode or Persistent location timing.
enum TrackerAvailability {
    static func isAllowed(locationMode: String, persistence: String) -> Bool {
        locationMode != "hot_cold" && persistence != "persistent"
    }

    static func isAllowed(modules: [VisualModule]) -> Bool {
        isAllowed(
            locationMode: revealChoice("location_mode", in: modules) ?? "fuzzy",
            persistence: revealChoice("persistence", in: modules) ?? "timed"
        )
    }

    /// Turns Tracker off when the reveal mode would make it useless. Returns true if changed.
    @discardableResult
    static func syncEnabled(in modules: inout [VisualModule]) -> Bool {
        guard let powerIdx = modules.firstIndex(where: { $0.id == "power_ups" }),
              let rowIdx = modules[powerIdx].rows.firstIndex(where: { $0.id == "tracker_enabled" })
        else { return false }
        let allowed = isAllowed(modules: modules)
        if allowed || modules[powerIdx].rows[rowIdx].flag == false {
            return false
        }
        modules[powerIdx].rows[rowIdx].flag = false
        return true
    }

    private static func revealChoice(_ id: String, in modules: [VisualModule]) -> String? {
        guard let reveal = modules.first(where: { $0.id == "reveal_fuzzy" }),
              let row = reveal.rows.first(where: { $0.id == id }),
              case let .options(_, values) = row.control,
              values.indices.contains(row.choice)
        else { return nil }
        return values[row.choice]
    }
}
