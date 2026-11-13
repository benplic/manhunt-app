import SwiftUI

struct PresetEditorView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    title: store.editingPresetID == nil ? "New preset" : "Edit preset",
                    subtitle: "Built from the server's module schema.",
                    onBack: store.closePreset
                )

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Preset name", text: $store.presetName)
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(HuntColor.paper)
                            .padding(12)
                            .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if let note = store.note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(HuntColor.warning)
                        }
                        HuntButton(
                            title: store.isSavingPreset
                                ? "Saving…"
                                : (store.editingPresetID == nil ? "Save preset" : "Save changes"),
                            action: { Task { await store.savePreset() } }
                        )
                        .disabled(store.isSavingPreset)
                        Button("New preset", action: store.beginNewPreset)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HuntColor.signal)
                        ForEach(store.savedPresets) { preset in
                            HStack {
                                Button(preset.name) { store.loadPreset(preset) }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HuntColor.signal)
                                Button("Rename") { store.loadPreset(preset) }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HuntColor.muted)
                                Button("Delete") { store.deletePreset(id: preset.id) }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HuntColor.warning)
                            }
                        }
                    }
                }

                ForEach($store.modules) { $module in
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            if module.locked {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.title)
                                        .font(.headline)
                                        .foregroundStyle(HuntColor.paper)
                                    Text(module.blurb)
                                        .font(.footnote)
                                        .foregroundStyle(HuntColor.muted)
                                }
                                ForEach($module.rows) { $row in
                                    revealRow(module: module, row: $row)
                                }
                            } else {
                                Toggle(isOn: $module.enabled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(module.title)
                                            .font(.headline)
                                            .foregroundStyle(HuntColor.paper)
                                        Text(module.blurb)
                                            .font(.footnote)
                                            .foregroundStyle(HuntColor.muted)
                                    }
                                }
                                .tint(HuntColor.signal)
                                if module.enabled {
                                    ForEach($module.rows) { $row in
                                        rowControl(row: $row)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }

    @ViewBuilder
    private func revealRow(module: VisualModule, row: Binding<VisualRow>) -> some View {
        if module.id != "reveal_fuzzy"
            || RevealFormVisibility.shows(rowID: row.wrappedValue.id, modules: store.modules) {
            rowControl(row: row)
        }
    }

    @ViewBuilder
    private func rowControl(row: Binding<VisualRow>) -> some View {
        switch row.wrappedValue.control {
        case .toggle:
            Toggle(row.wrappedValue.title, isOn: row.flag)
                .tint(HuntColor.signal)
                .foregroundStyle(HuntColor.paper)
        case let .stepper(min, max, step, suffix, _):
            if row.wrappedValue.stepperRangeIsUsable {
                Stepper(
                    value: Binding(
                        get: { Swift.min(max, Swift.max(min, row.wrappedValue.number)) },
                        set: { row.wrappedValue.number = Swift.min(max, Swift.max(min, $0)) }
                    ),
                    in: min...max,
                    step: step
                ) {
                    HStack {
                        Text(row.wrappedValue.title)
                        Spacer()
                        Text(stepperLabel(row.wrappedValue.number, suffix: suffix))
                            .foregroundStyle(HuntColor.signal)
                            .monospacedDigit()
                    }
                    .foregroundStyle(HuntColor.paper)
                }
            } else {
                Text("\(row.wrappedValue.title) \(stepperLabel(row.wrappedValue.number, suffix: suffix))")
                    .foregroundStyle(HuntColor.paper)
            }
        case let .options(display, values):
            let labels = display.count == values.count ? display : values
            VStack(alignment: .leading, spacing: 6) {
                Text(row.wrappedValue.title)
                    .font(.subheadline)
                    .foregroundStyle(HuntColor.muted)
                if values.isEmpty {
                    Text("No choices")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                } else {
                    Picker(row.wrappedValue.title, selection: optionSelection(row: row, values: values)) {
                        ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                            Text(index < labels.count ? labels[index] : value).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    /// Selection is the schema string, clamped into the option list.
    private func optionSelection(row: Binding<VisualRow>, values: [String]) -> Binding<String> {
        Binding(
            get: {
                let choice = min(max(0, row.wrappedValue.choice), values.count - 1)
                return values[choice]
            },
            set: { newValue in
                if let index = values.firstIndex(of: newValue) {
                    row.wrappedValue.choice = index
                }
            }
        )
    }

    private func stepperLabel(_ value: Double, suffix: String) -> String {
        let number = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }
}
