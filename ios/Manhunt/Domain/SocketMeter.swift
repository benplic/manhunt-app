import Foundation

/// What the four-bar meter reads from the socket. A value, so the mapping is a pure function.
struct SocketHealth: Equatable, Sendable {
    /// Open and the server has said welcome.
    var connected: Bool
    /// Consecutive drops since the last stable connection. 0 while healthy.
    var failureStreak: Int
    /// When the last server message of any kind arrived, or nil before the first one.
    var lastMessageAt: Date?
    /// False when the system reports no usable network path.
    var networkAvailable: Bool = true
}

/// Four-bar meter for YOUR socket to the hunt server. It is not GPS quality and it says
/// nothing about other players. Keep identical to `web/src/game/socketMeter.ts`.
///
/// - 4 bars: connected, last server message within `staleAfter`
/// - 3 bars: connected, last server message older than `staleAfter`
/// - 2 bars: not connected, first retry (or the first connect still in progress)
/// - 1 bar: not connected, repeated failures
/// - 0 bars: down, the device has no network or failures kept piling up
enum SocketMeter {
    /// The 5 second window is decided by the user.
    static let staleAfter: TimeInterval = 5
    /// From this many failed attempts in a row the socket counts as down.
    /// TODO: tune with playtest data.
    static let downAfterFailures = 5

    enum Label: String, Equatable, Sendable {
        case good, slow, reconnecting, unstable, down
    }

    struct Reading: Equatable, Sendable {
        var bars: Int
        var label: Label

        /// The word carries the meaning; the bars are decoration, so color is never the only signal.
        var accessibilityLabel: String { "Connection: \(label.rawValue)" }
    }

    static func reading(for health: SocketHealth, now: Date = Date()) -> Reading {
        if health.connected {
            // A connected socket that has heard nothing yet is as quiet as it gets.
            let quiet = age(of: health, now: now).map { $0 > staleAfter } ?? true
            return quiet ? Reading(bars: 3, label: .slow) : Reading(bars: 4, label: .good)
        }
        if !health.networkAvailable || health.failureStreak >= downAfterFailures {
            return Reading(bars: 0, label: .down)
        }
        if health.failureStreak >= 2 {
            return Reading(bars: 1, label: .unstable)
        }
        return Reading(bars: 2, label: .reconnecting)
    }

    /// Seconds since the last server message, never negative; nil before the first message.
    static func age(of health: SocketHealth, now: Date = Date()) -> TimeInterval? {
        health.lastMessageAt.map { max(0, now.timeIntervalSince($0)) }
    }

    /// Short sentence for the tap explanation, including the last message age when known.
    static func explanation(for health: SocketHealth, now: Date = Date()) -> String {
        let current = reading(for: health, now: now)
        let base: String
        switch current.label {
        case .good: base = "Connected. Updates are arriving."
        case .slow: base = "Connected, but the last update was a while ago."
        case .reconnecting: base = "Reconnecting to the hunt server."
        case .unstable: base = "Your connection keeps dropping. Updates may be late."
        case .down: base = "No connection to the hunt server."
        }
        guard let seconds = age(of: health, now: now) else {
            return "\(base) No update yet."
        }
        return "\(base) Last update \(Int(seconds.rounded()))s ago."
    }
}
