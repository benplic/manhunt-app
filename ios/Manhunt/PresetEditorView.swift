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
                        HuntButton(
                            title: store.editingPresetID == nil ? "Save preset" : "Save changes",
                            action: { Task { await store.savePreset() } }
                        )
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
            .padding(20)
        }
        .background(HuntColor.ink)
    }

    @ViewBuilder
    private func rowControl(row: Binding<VisualRow>) -> some View {
        switch row.wrappedValue.control {
        case .toggle:
            Toggle(row.wrappedValue.title, isOn: row.flag)
                .tint(HuntColor.signal)
                .foregroundStyle(HuntColor.paper)
        case let .stepper(min, max, step, suffix, _):
            Stepper(value: row.number, in: min...max, step: step) {
                HStack {
                    Text(row.wrappedValue.title)
                    Spacer()
                    Text(stepperLabel(row.wrappedValue.number, suffix: suffix))
                        .foregroundStyle(HuntColor.signal)
                        .monospacedDigit()
                }
                .foregroundStyle(HuntColor.paper)
            }
        case let .options(display, _):
            VStack(alignment: .leading, spacing: 6) {
                Text(row.wrappedValue.title)
                    .font(.subheadline)
                    .foregroundStyle(HuntColor.muted)
                Picker(row.wrappedValue.title, selection: row.choice) {
                    ForEach(display.indices, id: \.self) { index in
                        Text(display[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func stepperLabel(_ value: Double, suffix: String) -> String {
        let number = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }
}
