import MapKit
import SwiftUI

struct ArenaEditorView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: store.arenaID == "new" ? "New arena" : store.arena.name, subtitle: "Center the crosshair, then drop a point.", onBack: {
                    store.goHome()
                })
                Picker("Tool", selection: $store.tool) {
                    ForEach(ArenaTool.allCases) { tool in
                        Text(tool.rawValue).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HuntMap(
                boundary: store.draftBoundary,
                zones: store.draftZones,
                people: [],
                showHiders: false,
                showSeekers: false,
                fuzzyHiders: false,
                region: editorRegion,
                onDrop: { store.drop(at: $0) }
            )
            .clipShape(RoundedRectangle(cornerRadius: 0))

            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(HuntColor.paper)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(store.editorIssues, id: \.self) { issue in
                    Text(issue)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                }
                HStack {
                    legend(HuntColor.signal, "Play")
                    legend(HuntColor.safe, "Safe")
                    legend(HuntColor.warning, "Out")
                    legend(HuntColor.seeker, "Spawn")
                    Spacer()
                    Button("Undo", action: store.undoDrop)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HuntColor.signal)
                }
                HuntButton(title: "Save arena", action: store.saveArena)
            }
            .padding(16)
            .background(HuntColor.ink)
        }
        .background(HuntColor.ink)
    }

    private var editorRegion: MKCoordinateRegion {
        if store.draftBoundary.count >= 3 {
            return VisualArena(id: "draft", name: "", place: "", boundary: store.draftBoundary, zones: []).region
        }
        return store.arena.region
    }

    private var statusLine: String {
        if store.editor.hasPendingSafeCenter {
            return "Safe center set. Drop a second point to set the radius."
        }
        if store.tool == .playArea && store.draftBoundary.count < 3 {
            return "Add at least 3 points to close the play area."
        }
        return "Yellow is the play area. Other zones have to sit inside it."
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(HuntColor.muted)
        }
    }
}
