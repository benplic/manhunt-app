import SwiftUI

/// What the host is editing from the lobby.
enum LobbyEditKind: String, Identifiable {
    case rules
    case map

    var id: String { rawValue }
}

/// Host-only editor opened from the lobby. Rules edit the timers the server already owns;
/// the map edit resizes the play circle. Both go through the lobby-only server endpoints, so a
/// late tap after the hunt starts is rejected with WRONG_PHASE instead of silently applied.
///
/// TODO: reuse `PresetEditorView` for the full rule list. It is built around saved presets and
/// the create flow, so it needs a "lobby game" mode first. Today this sheet covers the timers.
/// TODO: moving the play circle's center or drawing a polygon needs a server endpoint that
/// accepts a full arena in the lobby. Only the radius can change today, and only on a circle
/// arena (the lobby hides "Edit map" otherwise, because the server would replace a polygon).
struct LobbyEditSheet: View {
    @Environment(AppStore.self) private var store
    let kind: LobbyEditKind
    var dismiss: () -> Void

    @State private var draft: LobbyRuleDraft
    @State private var radiusM: Double
    @State private var isSaving = false
    private let initialRadiusM: Double?

    init(kind: LobbyEditKind, timers: TimersDTO?, radiusM: Double?, dismiss: @escaping () -> Void) {
        self.kind = kind
        self.dismiss = dismiss
        initialRadiusM = radiusM
        _draft = State(initialValue: LobbyRuleDraft(timers: timers))
        _radiusM = State(initialValue: radiusM ?? 400)
    }

    private var current: LobbyRuleDraft { LobbyRuleDraft(timers: store.match?.snapshot.timers) }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .rules: rulesSection
                case .map: mapSection
                }
                if let note = store.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                }
            }
            .navigationTitle(kind == .rules ? "Edit rules" : "Edit map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Apply") { apply() }
                        .disabled(!canApply || isSaving)
                        .accessibilityIdentifier("lobby-edit-apply")
                }
            }
        }
    }

    @ViewBuilder
    private var rulesSection: some View {
        Section("Timers") {
            Stepper(value: $draft.headStartS, in: LobbyRuleDraft.headStartRange, step: 15) {
                Text("Head start: \(draft.headStartS) s")
            }
            Stepper(value: $draft.timeLimitMinutes, in: LobbyRuleDraft.timeLimitMinutesRange, step: 5) {
                Text("Time limit: \(draft.timeLimitMinutes) min")
            }
            if let interval = draft.revealIntervalS {
                Stepper(
                    value: Binding(
                        get: { interval },
                        set: { draft.revealIntervalS = $0 }
                    ),
                    in: LobbyRuleDraft.revealIntervalRange,
                    step: 10
                ) {
                    Text("Hider reveal every: \(interval) s")
                }
            }
        }
        ForEach(draft.errors(against: current), id: \.self) { message in
            Text(message)
                .font(.footnote)
                .foregroundStyle(HuntColor.warning)
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        Section("Play area") {
            Stepper(
                value: $radiusM,
                in: ArenaValidator.minPlayRadiusMeters...ArenaValidator.maxPlayRadiusMeters,
                step: 50
            ) {
                Text("Radius: \(Int(radiusM)) m")
            }
            Text("Players outside the circle risk an out-of-bounds tag.")
                .font(.footnote)
                .foregroundStyle(HuntColor.muted)
        }
    }

    private var canApply: Bool {
        switch kind {
        case .rules:
            return draft.errors(against: current).isEmpty && draft.overrides(against: current) != nil
        case .map:
            // Unchanged is not an edit, and a polygon arena has no radius to change.
            guard let existing = initialRadiusM else { return false }
            return ArenaValidator.isValidPlayRadius(radiusM) && radiusM != existing
        }
    }

    private func apply() {
        isSaving = true
        Task {
            let accepted: Bool
            switch kind {
            case .rules:
                guard let overrides = draft.overrides(against: current) else {
                    isSaving = false
                    return
                }
                accepted = await store.updateLobbyRules(overrides)
            case .map:
                accepted = await store.setLobbyRadius(radiusM)
            }
            isSaving = false
            if accepted { dismiss() }
        }
    }
}
