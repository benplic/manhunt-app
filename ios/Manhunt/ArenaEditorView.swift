import MapKit
import SwiftUI

struct ArenaEditorView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var editor = store.editor
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: editor.name, subtitle: "Center the crosshair, then drop a point.", onBack: {
                    store.goHome()
                })
                TextField("Arena name", text: $editor.name)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(HuntColor.paper)
                    .padding(12)
                    .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                vertexTools
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
        if store.tool == .playArea && store.editor.vertexToMove != nil {
            return "Drop a point to move the selected vertex."
        }
        if store.tool == .playArea && store.editor.selectedEdge != nil {
            return "Drop a point to split the selected edge."
        }
        if store.tool == .playArea {
            return "Select an edge, then drop a point on it. A new point splits that edge."
        }
        return "Yellow is the play area. A bowtie is still rejected on save."
    }

    @ViewBuilder
    private var vertexTools: some View {
        if store.tool == .playArea && store.editor.boundary.vertices.count >= 3 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.editor.boundary.vertices.indices, id: \.self) { index in
                        Button("Edge \(index + 1)") { store.selectPlayEdge(index) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.editor.selectedEdge == index ? HuntColor.ink : HuntColor.signal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                store.editor.selectedEdge == index ? HuntColor.signal : HuntColor.inkRaised,
                                in: Capsule()
                            )
                        Button("Move \(index + 1)") { store.selectPlayVertex(index) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HuntColor.paper)
                        Button("Delete \(index + 1)") { store.deletePlayVertex(index) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HuntColor.warning)
                    }
                }
            }
        }
        ForEach(store.editor.zones) { zone in
            HStack {
                TextField(
                    "Zone name",
                    text: Binding(
                        get: { zone.name },
                        set: { store.renameZone(id: zone.id, to: $0) }
                    )
                )
                .foregroundStyle(HuntColor.paper)
                Button("Delete zone") { store.deleteZone(id: zone.id) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HuntColor.warning)
            }
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(HuntColor.muted)
        }
    }
}
