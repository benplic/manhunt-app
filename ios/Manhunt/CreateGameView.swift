import SwiftUI

struct CreateGameView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let activePreset = RulePreset.matching(modules: store.modules)
        let isCircleArena = store.selectedArena?.boundaryCircle != nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "New game", subtitle: "Pick a park and a ruleset.", onBack: store.goHome)

                Text("ARENA")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(HuntColor.muted)
                ForEach(store.arenas) { arena in
                    Button {
                        store.arenaID = arena.id.uuidString
                    } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(arena.name)
                                            .font(.headline)
                                            .foregroundStyle(HuntColor.paper)
                                        if arena.boundaryCircle != nil {
                                            Text("Circle")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(HuntColor.signal.opacity(0.2), in: Capsule())
                                                .foregroundStyle(HuntColor.signal)
                                        }
                                    }
                                    Text("\(arena.zones.count) zones")
                                        .font(.subheadline)
                                        .foregroundStyle(HuntColor.muted)
                                }
                                Spacer()
                                Image(systemName: store.arenaID == arena.id.uuidString ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.arenaID == arena.id.uuidString ? HuntColor.signal : HuntColor.muted)
                            }
                        }
                    }
                    .buttonStyle(.huntPress(.medium))
                }

                HStack {
                    Text("HOUSE RULES")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(HuntColor.muted)
                    Spacer()
                    if activePreset == nil {
                        Text("Custom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HuntColor.signal)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RulePreset.allCases) { preset in
                            let selected = activePreset == preset
                            Button {
                                store.applyRulePreset(preset)
                            } label: {
                                Text(preset.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        selected ? HuntColor.seeker : HuntColor.inkRaised,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().stroke(selected ? HuntColor.seeker : HuntColor.line, lineWidth: 1)
                                    )
                                    .foregroundStyle(HuntColor.paper)
                            }
                            .buttonStyle(.huntPress(.selection))
                            .accessibilityIdentifier("preset-\(preset.rawValue)")
                        }
                    }
                }

                Text(activePreset?.blurb ?? "Custom: adjusted from base rules.")
                    .font(.footnote)
                    .foregroundStyle(HuntColor.muted)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        quickStepperRow(
                            title: "Round length",
                            moduleID: "win",
                            rowID: "time_limit",
                            valueText: { "\(Int($0.rounded())) min" }
                        )
                        Divider().background(HuntColor.line)
                        quickStepperRow(
                            title: "Head start",
                            moduleID: "head_start",
                            rowID: "duration",
                            ensureEnabled: true,
                            valueText: { formatDuration(Int($0.rounded())) }
                        )
                        Divider().background(HuntColor.line)
                        quickStepperRow(
                            title: "Pings",
                            moduleID: "reveal_fuzzy",
                            rowID: "interval",
                            ensureEnabled: true,
                            valueText: { "Every \(formatDuration(Int($0.rounded())))" }
                        )
                        Divider().background(HuntColor.line)
                        zoneShrinkRow(isCircleArena: isCircleArena)
                        Divider().background(HuntColor.line)
                        Button("All rules", action: store.openPreset)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HuntColor.signal)
                    }
                }

                HuntButton(title: "Open lobby", systemImage: "person.3", action: store.openLobbyAsHost)
                    .accessibilityIdentifier("open-lobby")
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }

    @ViewBuilder
    private func quickStepperRow(
        title: String,
        moduleID: String,
        rowID: String,
        ensureEnabled: Bool = false,
        valueText: @escaping (Double) -> String
    ) -> some View {
        if let mIdx = store.modules.firstIndex(where: { $0.id == moduleID }),
           let rIdx = store.modules[mIdx].rows.firstIndex(where: { $0.id == rowID }),
           case let .stepper(min, max, step, _, _) = store.modules[mIdx].rows[rIdx].control {
            let current = store.modules[mIdx].rows[rIdx].number
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(HuntColor.muted)
                    Text(valueText(current))
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(HuntColor.paper)
                        .monospacedDigit()
                }
                Spacer()
                HStack(spacing: 2) {
                    Button {
                        if ensureEnabled { store.modules[mIdx].enabled = true }
                        store.modules[mIdx].rows[rIdx].number = Swift.max(min, current - step)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 40, height: 34)
                            .background(HuntColor.ink)
                            .foregroundStyle(HuntColor.paper)
                    }
                    .buttonStyle(.huntPress(.light))
                    .disabled(current <= min)
                    Button {
                        if ensureEnabled { store.modules[mIdx].enabled = true }
                        store.modules[mIdx].rows[rIdx].number = Swift.min(max, current + step)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 40, height: 34)
                            .background(HuntColor.ink)
                            .foregroundStyle(HuntColor.paper)
                    }
                    .buttonStyle(.huntPress(.light))
                    .disabled(current >= max)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func zoneShrinkRow(isCircleArena: Bool) -> some View {
        if let mIdx = store.modules.firstIndex(where: { $0.id == "zone_shrink" }) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    isOn: Binding(
                        get: { isCircleArena && store.modules[mIdx].enabled },
                        set: { store.modules[mIdx].enabled = $0 }
                    )
                ) {
                    Text("Zone shrinks")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCircleArena ? HuntColor.paper : HuntColor.muted)
                }
                .tint(HuntColor.signal)
                .disabled(!isCircleArena)
                .accessibilityIdentifier("zone-shrink-toggle")

                if !isCircleArena {
                    Text("Zone shrinking is only available for circle play areas.")
                        .font(.caption)
                        .foregroundStyle(HuntColor.muted)
                } else if store.modules[mIdx].enabled {
                    quickStepperRow(
                        title: "Shrink interval",
                        moduleID: "zone_shrink",
                        rowID: "every",
                        valueText: { "Every \(Int($0.rounded())) min" }
                    )
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
