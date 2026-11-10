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
}

enum PowerUpRules {
    static func decide(_ request: PurchaseRequest) -> PurchaseDecision {
        if request.balance < request.cost { return .denied(.insufficientPoints) }
        if request.cooldownRemaining > 0 { return .denied(.coolingDown) }
        if request.phase != .active { return .denied(.wrongPhase) }
        if request.role != request.requiredRole { return .denied(.wrongRole) }
        if request.status == .eliminated { return .denied(.eliminated) }
        if request.requiresTarget && !request.hasTarget { return .denied(.needsTarget) }
        if request.requiresTarget && request.hasTarget && !request.targetInsidePlayArea {
            return .denied(.targetOutside)
        }
        return .allowed
    }

    /// Decoy is tappable when every rule passes except picking a map target.
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
}
