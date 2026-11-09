import Foundation

/// JSON value the classic preset accepts: number, bool, or string.
enum RuleValue: Encodable, Equatable {
    case int(Int)
    case bool(Bool)
    case string(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}

/// Maps the preset form onto server module ids. Volunteer has no server mode yet.
enum PresetOverrides {
    static func from(modules: [VisualModule]) -> [String: [String: RuleValue]] {
        var overrides: [String: [String: RuleValue]] = [:]
        for module in modules {
            guard let serverID = serverID(for: module.id) else { continue }
            var fields: [String: RuleValue] = [:]
            if serverID != "roles", serverID != "win" {
                fields["enabled"] = .bool(module.enabled)
            }
            for row in module.rows {
                if let mapped = field(moduleID: serverID, row: row) {
                    fields[mapped.key] = mapped.value
                }
            }
            if !fields.isEmpty {
                overrides[serverID] = fields
            }
        }
        return overrides
    }

    private static func serverID(for visualID: String) -> String? {
        switch visualID {
        case "reveal": return "reveal_fuzzy"
        case "tag": return "tag_policy"
        case "zones": return "zone_policy"
        case "signal": return "signal_loss"
        default: return visualID
        }
    }

    private static func field(moduleID: String, row: VisualRow) -> (key: String, value: RuleValue)? {
        let whole = Int(row.number.rounded())
        switch (moduleID, row.id) {
        case ("roles", "mode"):
            // TODO: "Volunteer" is not a server mode. Treat it as manual until it exists.
            return ("mode", .string(row.choice == 0 ? "random" : "manual"))
        case ("roles", "hiders"):
            return ("hider_count", .int(min(20, max(1, whole))))
        case ("head_start", "duration"):
            return ("duration", .int(min(600, max(15, whole))))
        case ("head_start", "lock"):
            return ("seeker_lock", .string(row.choice == 1 ? "spawn_zone" : "locked_map"))
        case ("reveal_fuzzy", "interval"):
            return ("interval", .int(min(600, max(20, whole))))
        case ("reveal_fuzzy", "show"):
            return ("display", .int(min(60, max(5, whole))))
        case ("reveal_fuzzy", "fuzz"):
            return ("fuzz", .int(min(100, max(0, whole))))
        case ("hot_cold", "on"):
            return ("enabled", .bool(row.flag))
        case ("tag_policy", "radius"):
            return ("radius_m", .int(min(5, max(1, whole))))
        case ("tag_policy", "result"):
            return ("result", .string(row.choice == 1 ? "convert" : "eliminate"))
        case ("zone_policy", "countdown"):
            return ("oob_countdown", .int(min(120, max(5, whole))))
        case ("zone_policy", "safe_time"):
            return ("safe_visit", .int(min(300, max(5, whole))))
        case ("signal_loss", "silence"):
            return ("silence", .int(min(300, max(15, whole))))
        case ("win", "condition"):
            let name = ["all_caught", "time_limit", "either"][min(2, max(0, row.choice))]
            return ("condition", .string(name))
        case ("win", "limit"):
            return ("time_limit", .int(min(180, max(5, whole))))
        default:
            return nil
        }
    }
}
