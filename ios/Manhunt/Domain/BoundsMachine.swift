import Foundation

enum BoundsPhase: Equatable {
    case inside
    case warning
    case countdown(remainingSeconds: Int)
    case penalized
}

/// Client helper that mirrors the server's out-of-bounds state machine so the
/// editor and tests can reason about it without a network.
struct BoundsMachine {
    var phase: BoundsPhase = .inside

    mutating func receive(isOutside: Bool, countdownSeconds: Int) {
        if !isOutside {
            phase = .inside
            return
        }
        switch phase {
        case .inside:
            phase = .warning
        case .warning:
            phase = .countdown(remainingSeconds: countdownSeconds)
        case .countdown(let remaining):
            if remaining <= 1 {
                phase = .penalized
            } else {
                phase = .countdown(remainingSeconds: remaining - 1)
            }
        case .penalized:
            phase = .penalized
        }
    }
}
