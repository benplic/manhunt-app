import MapKit
import SwiftUI

struct ArenaEditorView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var editor = store.editor
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button(action: store.goHome) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(HuntColor.inkRaised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Arena name", text: $editor.name)
                            .font(HuntFont.title(32))
                            .foregroundStyle(HuntColor.paper)
                            .textInputAutocapitalization(.words)
                        Text("Center the crosshair, then drop a point.")
                            .font(.footnote)
                            .foregroundStyle(HuntColor.muted)
                    }
                }
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
                pendingVertices: store.draftPending,
                pendingCircleCenter: store.draftCircleCenter,
                highlightedEdge: store.draftHighlightedEdge,
                homeCoordinate: store.editorHomeCoordinate,
                onDrop: { store.drop(at: $0) },
                onCrosshair: { store.updateEditorCrosshair($0) }
            )
            .clipShape(RoundedRectangle(cornerRadius: 0))

            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(HuntColor.paper)
                    .fixedSize(horizontal: false, vertical: true)
                if let notice = store.editor.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                }
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
        let boundary = store.editor.boundary.vertices
        let isNew = store.arenaID == "new" && boundary.count < 3
        return EditorCamera.region(user: storeUserPoint, boundary: boundary, isNew: isNew)
    }

    private var storeUserPoint: GeoPoint? {
        guard let coordinate = store.editorHomeCoordinate else { return nil }
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var statusLine: String {
        if store.editor.hasPendingSafeCenter {
            return "Safe center set. Drop a second point to set the radius."
        }
        if store.tool == .safe, store.draftCircleCenter != nil {
            return "Safe center set. Drop a second point to set the radius."
        }
        if pendingZonePointsCount == 1 {
            return "First point set. Drop the other end of the line."
        }
        if pendingZonePointsCount == 2 {
            return "Line set. The next point closes the shape."
        }
        if store.tool == .playArea && store.draftBoundary.count == 1 {
            return "First point set. Drop the other end of the line."
        }
        if store.tool == .playArea && store.draftBoundary.count == 2 {
            return "Line set. The next point closes the play area."
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
            return "Drop on a highlighted edge to add a point."
        }
        if store.tool == .outOfBounds || store.tool == .spawn {
            return "Drop on a highlighted edge to add a point, or start a new shape."
        }
        return "Yellow is the play area."
    }

    private var pendingZonePointsCount: Int {
        guard store.tool == .outOfBounds || store.tool == .spawn else { return 0 }
        return store.draftPending.count
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
        if store.tool == .outOfBounds || store.tool == .spawn {
            Button("New shape", action: store.beginNewZoneShape)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HuntColor.signal)
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
