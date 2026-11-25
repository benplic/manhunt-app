import Foundation

/// Host-editable rules in the lobby. Limits mirror RANGES in server/app/presets/classic.py,
/// which is the authority: the server rejects anything outside them with VALIDATION_FAILED.
/// Mirror of web/src/game/lobbyRules.ts.
struct LobbyRuleDraft: Equatable {
    static let headStartRange = 15...600
    static let timeLimitMinutesRange = 5...180
    static let revealIntervalRange = 20...600

    var headStartS: Int
    var timeLimitMinutes: Int
    /// Nil when hider reveals are off in this match, so there is no interval to edit.
    var revealIntervalS: Int?

    init(headStartS: Int, timeLimitMinutes: Int, revealIntervalS: Int?) {
        self.headStartS = headStartS
        self.timeLimitMinutes = timeLimitMinutes
        self.revealIntervalS = revealIntervalS
    }

    init(timers: TimersDTO?) {
        headStartS = timers?.headStartS ?? 60
        timeLimitMinutes = Int(((Double(timers?.timeLimitS ?? 1800)) / 60).rounded())
        revealIntervalS = timers?.revealIntervalS
    }

    /// One message per field that is out of range. Empty means the draft can be sent.
    var errors: [String] { errors(against: nil) }

    /// With `current`, only changed fields are checked. A match with head start off reports
    /// 0 seconds, which is outside the editable range and must not block an unrelated edit.
    func errors(against current: LobbyRuleDraft?) -> [String] {
        var found: [String] = []
        if current?.headStartS != headStartS, !Self.headStartRange.contains(headStartS) {
            found.append("Head start must be between \(Self.headStartRange.lowerBound) and \(Self.headStartRange.upperBound).")
        }
        if current?.timeLimitMinutes != timeLimitMinutes, !Self.timeLimitMinutesRange.contains(timeLimitMinutes) {
            found.append("Time limit must be between \(Self.timeLimitMinutesRange.lowerBound) and \(Self.timeLimitMinutesRange.upperBound).")
        }
        if let interval = revealIntervalS, interval != current?.revealIntervalS,
           !Self.revealIntervalRange.contains(interval) {
            found.append("Reveal interval must be between \(Self.revealIntervalRange.lowerBound) and \(Self.revealIntervalRange.upperBound).")
        }
        return found
    }

    /// Only the fields that changed, shaped for POST /v1/games/{id}/rules. Nil when nothing changed.
    func overrides(against current: LobbyRuleDraft) -> [String: [String: RuleValue]]? {
        var result: [String: [String: RuleValue]] = [:]
        if headStartS != current.headStartS {
            result["head_start"] = ["duration": .int(headStartS)]
        }
        if timeLimitMinutes != current.timeLimitMinutes {
            result["win"] = ["time_limit": .int(timeLimitMinutes)]
        }
        if let interval = revealIntervalS, interval != current.revealIntervalS {
            result["reveal_fuzzy"] = ["interval": .int(interval)]
        }
        return result.isEmpty ? nil : result
    }
}
