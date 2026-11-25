import Foundation

/// Dock line for a hot/cold hint. The server owns the band, meters, and bearing.
enum HintCopy {
    /// Nil means "show nothing". A hider with no payload (Classic seeker reveal is Off)
    /// gets no line, and the caller collapses the whole row.
    static func line(role: PlayerRole, hint: HintDTO?) -> String? {
        if role == .hider {
            guard let hint, let band = hint.band else {
                return nil
            }
            return sentence(
                name: hint.name ?? "A seeker",
                band: band,
                meters: hint.meters,
                bearing: hint.bearingDeg
            )
        }
        guard role == .seeker, let hint, let band = hint.band else {
            return "No hint yet."
        }
        return sentence(
            name: hint.name ?? "A hider",
            band: band,
            meters: hint.meters,
            bearing: hint.bearingDeg
        )
    }

    private static func sentence(name: String, band: String, meters: Int?, bearing: Int?) -> String {
        let metersText = meters.map(String.init) ?? "?"
        guard let bearing else {
            return "\(name) is \(band), \(metersText) m"
        }
        return "\(name) is \(band), \(metersText) m, \(cardinal(for: bearing))"
    }

    /// Preset / form help for when seekers get hot/cold hints.
    static func hintsHelp(locationMode: String, hintsEnabled: Bool) -> String {
        switch locationMode {
        case "hot_cold":
            return "Hints are always on in Hot/cold."
        case "precise":
            return "Hints are off in Precise."
        default:
            return hintsEnabled
                ? "Hints are on with Fuzzy."
                : "Hints are off while the Fuzzy Hints toggle is off."
        }
    }

    /// Eight compass points. 0 is north, and the bins are 45 degrees wide.
    static func cardinal(for degrees: Int) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let turn = ((degrees % 360) + 360) % 360
        let index = Int((Double(turn) + 22.5) / 45.0) % 8
        return names[index]
    }
}
