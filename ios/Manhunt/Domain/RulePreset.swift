import Foundation

/// Base house-rule presets shown on CreateGameView.
/// Standard matches the server's Classic defaults (30 min round, 60 s head start, 60 s pings).
enum RulePreset: String, CaseIterable, Identifiable {
    case quick = "Quick"
    case standard = "Standard"
    case bigPark = "Big park"

    var id: String { rawValue }

    var roundMinutes: Int {
        switch self {
        case .quick: 15
        case .standard: 30
        case .bigPark: 60
        }
    }

    var headStartSeconds: Int {
        switch self {
        case .quick: 30
        case .standard: 60
        case .bigPark: 180
        }
    }

    var pingSeconds: Int {
        switch self {
        case .quick: 40
        case .standard: 60
        case .bigPark: 120
        }
    }

    var blurb: String {
        switch self {
        case .quick: "Quick: 15 min round, 30 s head start, 40 s pings."
        case .standard: "Standard: Classic Manhunt defaults."
        case .bigPark: "Big park: 60 min round, 3 min head start, 2 min pings."
        }
    }

    func apply(to modules: inout [VisualModule]) {
        setRow(in: &modules, moduleID: "win", rowID: "time_limit", number: Double(roundMinutes))
        setEnabled(in: &modules, moduleID: "head_start", enabled: true)
        setRow(in: &modules, moduleID: "head_start", rowID: "duration", number: Double(headStartSeconds))
        setRow(in: &modules, moduleID: "reveal_fuzzy", rowID: "interval", number: Double(pingSeconds))
    }

    static func matching(modules: [VisualModule]) -> RulePreset? {
        let round = rowNumber(in: modules, moduleID: "win", rowID: "time_limit")
        let hsEnabled = moduleEnabled(in: modules, moduleID: "head_start")
        let hs = rowNumber(in: modules, moduleID: "head_start", rowID: "duration")
        let ping = rowNumber(in: modules, moduleID: "reveal_fuzzy", rowID: "interval")
        guard hsEnabled == true else { return nil }
        return allCases.first {
            Int(round?.rounded() ?? -1) == $0.roundMinutes
                && Int(hs?.rounded() ?? -1) == $0.headStartSeconds
                && Int(ping?.rounded() ?? -1) == $0.pingSeconds
        }
    }

    private static func moduleEnabled(in modules: [VisualModule], moduleID: String) -> Bool? {
        modules.first { $0.id == moduleID }?.enabled
    }

    private static func rowNumber(
        in modules: [VisualModule],
        moduleID: String,
        rowID: String
    ) -> Double? {
        modules.first { $0.id == moduleID }?.rows.first { $0.id == rowID }?.number
    }

    private func setEnabled(in modules: inout [VisualModule], moduleID: String, enabled: Bool) {
        guard let idx = modules.firstIndex(where: { $0.id == moduleID }) else { return }
        modules[idx].enabled = enabled
    }

    private func setRow(
        in modules: inout [VisualModule],
        moduleID: String,
        rowID: String,
        number: Double
    ) {
        guard let mIdx = modules.firstIndex(where: { $0.id == moduleID }),
              let rIdx = modules[mIdx].rows.firstIndex(where: { $0.id == rowID })
        else { return }
        modules[mIdx].rows[rIdx].number = number
        modules[mIdx].rows[rIdx].clampToControl()
    }
}

/// Read-only rules summary line for LobbyView from `timers`.
enum RulesSummary {
    static func line(timers: TimersDTO) -> String {
        var parts: [String] = [
            "\(max(1, timers.timeLimitS / 60)) min",
            timers.headStartS > 0 ? "\(clock(timers.headStartS)) head start" : "No head start",
        ]
        if let ping = timers.revealIntervalS {
            parts.append("\(clock(ping)) pings")
        } else {
            parts.append("No pings")
        }
        if timers.zone != nil {
            parts.append("Zone shrinks")
        }
        return parts.joined(separator: " · ")
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
