import Foundation

/// JSON value a module setting accepts: number, bool, or string.
enum RuleValue: Codable, Equatable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let whole = try? container.decode(Int.self) {
            self = .int(whole)
        } else if let number = try? container.decode(Double.self) {
            self = .double(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

/// Reads the schema-built form. Row ids are already server field names.
enum PresetOverrides {
    static func from(modules: [VisualModule]) -> [String: [String: RuleValue]] {
        var overrides: [String: [String: RuleValue]] = [:]
        for module in modules {
            var fields: [String: RuleValue] = [:]
            if module.tracksEnabled {
                fields["enabled"] = .bool(module.enabled)
            }
            for row in module.rows {
                fields[row.id] = row.wireValue()
            }
            if !fields.isEmpty {
                overrides[module.id] = fields
            }
        }
        return overrides
    }
}
