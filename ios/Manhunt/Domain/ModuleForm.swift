import Foundation

/// One field from `GET /v1/modules`. Defaults are mixed JSON, so decoding is by hand.
struct SchemaFieldDTO: Decodable, Equatable {
    var type: String
    var title: String
    var min: Double?
    var max: Double?
    var step: Double?
    var suffix: String
    var values: [String]
    var labels: [String]
    var defaultBool: Bool?
    var defaultNumber: Double?
    var defaultString: String?

    enum CodingKeys: String, CodingKey {
        case type, title, min, max, step, suffix, values, labels
        case defaultValue = "default"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? type
        min = try container.decodeIfPresent(Double.self, forKey: .min)
        max = try container.decodeIfPresent(Double.self, forKey: .max)
        step = try container.decodeIfPresent(Double.self, forKey: .step)
        suffix = try container.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        values = try container.decodeIfPresent([String].self, forKey: .values) ?? []
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        defaultBool = nil
        defaultNumber = nil
        defaultString = nil
        guard container.contains(.defaultValue) else { return }
        // Bool before number: JSON `true` must not be read as 1.
        if let flag = try? container.decode(Bool.self, forKey: .defaultValue) {
            defaultBool = flag
        } else if let whole = try? container.decode(Int.self, forKey: .defaultValue) {
            defaultNumber = Double(whole)
        } else if let number = try? container.decode(Double.self, forKey: .defaultValue) {
            defaultNumber = number
        } else if let text = try? container.decode(String.self, forKey: .defaultValue) {
            defaultString = text
        }
    }
}

struct ModuleSchemaDTO: Decodable, Equatable {
    var version: Int
    var title: String?
    var blurb: String?
    var locked: Bool
    var fieldOrder: [String]
    /// False when the payload left `field_order` out and the decoder sorted the keys.
    var fieldOrderWasProvided: Bool
    var fields: [String: SchemaFieldDTO]

    enum CodingKeys: String, CodingKey {
        case version, title, blurb, locked, fields
        case fieldOrder = "field_order"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        title = try container.decodeIfPresent(String.self, forKey: .title)
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        fields = try container.decodeIfPresent([String: SchemaFieldDTO].self, forKey: .fields) ?? [:]
        if let listed = try container.decodeIfPresent([String].self, forKey: .fieldOrder) {
            fieldOrder = listed
            fieldOrderWasProvided = true
        } else {
            fieldOrder = fields.keys.sorted()
            fieldOrderWasProvided = false
        }
    }
}

struct ModulesResponse: Decodable, Equatable {
    var modules: [String: ModuleSchemaDTO]
    var order: [String]
    /// False when the payload left `order` out. Alphabetical keys are not a host-facing order.
    var orderWasProvided: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modules = try container.decode([String: ModuleSchemaDTO].self, forKey: .modules)
        let listed = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        orderWasProvided = !listed.isEmpty
        order = orderWasProvided ? listed : modules.keys.sorted()
    }

    enum CodingKeys: String, CodingKey {
        case modules, order
    }
}

/// Builds the preset form from the module schema instead of a hand-written row list.
enum ModuleForm {
    /// Offline copy of `GET /v1/modules`. The server file is the source of truth;
    /// regenerate this JSON when `server/app/schemas/modules.py` changes.
    static func offlineModules() -> [VisualModule] {
        guard let bundledResponse else { return [] }
        return modules(from: bundledResponse)
    }

    /// Display names, blurbs, labels, and field order for a server that omitted them.
    /// A title the server did send is left alone.
    private static let bundledResponse: ModulesResponse? = {
        guard let url = Bundle.main.url(forResource: "OfflineModuleSchema", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(ModulesResponse.self, from: data)
        else { return nil }
        return response
    }()

    static func modules(from response: ModulesResponse) -> [VisualModule] {
        displayOrder(for: response).compactMap { id in
            guard var schema = response.modules[id] else { return nil }
            fillDisplayGaps(&schema, id: id)
            return module(id: id, schema: schema)
        }
    }

    /// Bundled card order when the payload did not send one. Unknown server modules stay at the end.
    private static func displayOrder(for response: ModulesResponse) -> [String] {
        guard !response.orderWasProvided, let bundledResponse else { return response.order }
        let known = bundledResponse.order.filter { response.modules[$0] != nil }
        let extras = response.order.filter { id in !known.contains(id) }
        return known.isEmpty ? response.order : known + extras
    }

    /// Copy omitted display strings from the bundled schema. `title == type` means the
    /// decoder had no title and stored the JSON type (`int`, `enum`).
    private static func fillDisplayGaps(_ schema: inout ModuleSchemaDTO, id: String) {
        guard let bundled = bundledResponse?.modules[id] else { return }
        if schema.title == nil { schema.title = bundled.title }
        if schema.blurb == nil { schema.blurb = bundled.blurb }
        if !schema.fieldOrderWasProvided {
            let known = bundled.fieldOrder.filter { schema.fields[$0] != nil }
            let extras = schema.fieldOrder.filter { key in !known.contains(key) }
            if !known.isEmpty {
                schema.fieldOrder = known + extras
            }
        }
        for key in schema.fields.keys {
            guard var field = schema.fields[key], let bundledField = bundled.fields[key] else { continue }
            if field.title == field.type {
                field.title = bundledField.title
            }
            if field.labels.count != field.values.count,
               bundledField.labels.count == bundledField.values.count,
               bundledField.values == field.values {
                field.labels = bundledField.labels
            }
            schema.fields[key] = field
        }
    }

    /// Copy saved `rule_presets.modules` back onto a schema-built form.
    static func apply(
        _ saved: [String: [String: RuleValue]],
        to modules: [VisualModule]
    ) -> [VisualModule] {
        modules.map { module in
            var copy = module
            guard let fields = saved[module.id] else { return copy }
            if copy.tracksEnabled, let enabled = fields["enabled"], case let .bool(flag) = enabled {
                copy.enabled = flag
            }
            for index in copy.rows.indices {
                if let value = fields[copy.rows[index].id] {
                    copy.rows[index].apply(value)
                }
            }
            return copy
        }
    }

    private static func module(id: String, schema: ModuleSchemaDTO) -> VisualModule? {
        // Points and effects have no host-facing fields. An empty card is not a control.
        if schema.fields.isEmpty { return nil }
        let locked = schema.locked
        let enabledField = schema.fields["enabled"]
        let tracksEnabled = !locked && enabledField?.type == "bool"
        var rows: [VisualRow] = []
        var seen: Set<String> = []
        for key in schema.fieldOrder where key != "enabled" {
            guard seen.insert(key).inserted, let field = schema.fields[key] else { continue }
            rows.append(row(id: key, field: field))
        }
        return VisualModule(
            id: id,
            title: schema.title ?? id,
            blurb: schema.blurb ?? "",
            enabled: locked ? true : (enabledField?.defaultBool ?? true),
            tracksEnabled: tracksEnabled,
            locked: locked,
            rows: rows
        )
    }

    private static func row(id: String, field: SchemaFieldDTO) -> VisualRow {
        let control: VisualRow.Control
        var choice = 0
        var number = field.defaultNumber ?? field.min ?? 0
        let flag = field.defaultBool ?? false
        switch field.type {
        case "bool":
            control = .toggle
        case "enum":
            let display = field.labels.count == field.values.count ? field.labels : field.values
            control = .options(display: display, values: field.values)
            if let raw = field.defaultString, let index = field.values.firstIndex(of: raw) {
                choice = index
            }
        default:
            let integer = field.type == "int"
            let min = field.min ?? 0
            let max = field.max ?? max(min, number)
            let step = field.step ?? 1
            control = .stepper(min: min, max: max, step: step, suffix: field.suffix, integer: integer)
            number = minValue(number, min: min, max: max)
        }
        return VisualRow(
            id: id,
            title: field.title,
            control: control,
            number: number,
            choice: choice,
            flag: flag
        )
    }

    private static func minValue(_ number: Double, min: Double, max: Double) -> Double {
        Swift.min(max, Swift.max(min, number))
    }
}

enum RevealFormVisibility {
    static func shows(rowID: String, modules: [VisualModule]) -> Bool {
        guard let reveal = modules.first(where: { $0.id == "reveal_fuzzy" }) else { return true }
        func choice(_ id: String) -> String? {
            guard let row = reveal.rows.first(where: { $0.id == id }),
                  case let .options(_, values) = row.control,
                  values.indices.contains(row.choice) else { return nil }
            return values[row.choice]
        }
        func flag(_ id: String) -> Bool {
            reveal.rows.first(where: { $0.id == id })?.flag ?? true
        }
        let mode = choice("location_mode") ?? "fuzzy"
        let hintsActive = mode == "hot_cold" || (mode == "fuzzy" && flag("hints_enabled"))
        switch rowID {
        case "persistence", "interval":
            return mode != "hot_cold"
        case "display":
            if mode == "hot_cold" {
                return choice("hints_persistence") != "persistent"
            }
            return choice("persistence") != "persistent"
        case "fuzz":
            return mode == "fuzzy"
        case "hints_enabled":
            return mode == "fuzzy"
        case "hints_persistence", "hints_interval":
            return hintsActive
        default:
            return true
        }
    }
}
