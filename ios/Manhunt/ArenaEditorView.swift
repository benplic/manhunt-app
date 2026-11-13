import MapKit
import SwiftUI

struct ArenaEditorView: View {
    @Environment(AppStore.self) private var store
    @State private var showLayers = false

    var body: some View {
        @Bindable var store = store
        @Bindable var editor = store.editor
        let livePreviewRadius = previewCircleRadiusMeters
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button(action: store.goHome) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(HuntColor.inkRaised, in: Circle())
                    }
                    .buttonStyle(.huntPress(.light))
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ArenaTool.allCases) { tool in
                            let selected = store.tool == tool
                            Button {
                                store.tool = tool
                                store.editor.tool = editorTool(from: tool)
                                store.editor.notice = nil
                                store.draftCircleCenter = store.editor.pendingCircleCenterForMap.map {
                                    VisualPoint(latitude: $0.latitude, longitude: $0.longitude)
                                }
                            } label: {
                                Label(tool.rawValue, systemImage: tool.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        selected ? HuntColor.signal : HuntColor.inkRaised,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().stroke(selected ? HuntColor.signal : HuntColor.line, lineWidth: 1)
                                    )
                                    .foregroundStyle(selected ? HuntColor.ink : HuntColor.paper)
                            }
                            .buttonStyle(.huntPress(.selection))
                            .accessibilityIdentifier("tool-\(tool.rawValue)")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HuntMap(
                boundary: store.draftBoundary,
                boundaryCircle: store.draftBoundaryCircle,
                zones: store.draftZones,
                people: [],
                showHiders: false,
                showSeekers: false,
                fuzzyHiders: false,
                region: editorRegion,
                pendingVertices: store.draftPending,
                pendingCircleCenter: store.draftCircleCenter,
                pendingCircleRadiusMeters: livePreviewRadius,
                highlightedEdge: store.draftHighlightedEdge,
                homeCoordinate: store.editorHomeCoordinate,
                frameID: store.editorFrameID,
                onDrop: { store.drop(at: $0) },
                onCrosshair: { store.updateEditorCrosshair($0) }
            )
            .overlay(alignment: .topTrailing) {
                Button { showLayers = true } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(HuntColor.inkRaised, in: Circle())
                        .foregroundStyle(HuntColor.paper)
                }
                .buttonStyle(.huntPress(.light))
                .accessibilityLabel("Layers")
                .padding(12)
            }
            .overlay(alignment: .topLeading) {
                if let radius = livePreviewRadius, store.tool == .playCircle {
                    Text("Radius: \(Int(radius.rounded())) m")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(HuntColor.paper)
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 0))

            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(HuntColor.paper)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = store.editorWarning {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                        .lineLimit(3)
                }
                vertexTools
                HStack {
                    legend(HuntColor.signal, "Play")
                    legend(HuntColor.safe, "Safe")
                    legend(HuntColor.warning, "Out")
                    legend(HuntColor.seeker, "Spawn")
                    Spacer()
                    if !store.draftBoundary.isEmpty || store.draftBoundaryCircle != nil || store.editor.hasPendingPlayCircleCenter {
                        Button("Clear play area", action: store.clearPlayArea)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HuntColor.warning)
                    }
                    Button("Undo", action: store.undoDrop)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HuntColor.signal)
                }
                HuntButton(
                    title: store.isSavingArena ? "Saving…" : "Save arena",
                    action: store.saveArena
                )
                .disabled(store.isSavingArena)
            }
            .padding(16)
            .background(HuntColor.ink)
        }
        .background(HuntColor.ink)
        .sheet(isPresented: $showLayers) {
            ZoneLayersSheet { showLayers = false }
                .presentationDetents([.medium, .large])
        }
    }

    private var previewCircleRadiusMeters: Double? {
        guard store.tool == .playCircle,
              store.editor.hasPendingPlayCircleCenter,
              let center = store.draftCircleCenter,
              let crosshair = store.draftCrosshair else { return nil }
        return ArenaGeometry.meters(
            from: GeoPoint(latitude: center.latitude, longitude: center.longitude),
            to: GeoPoint(latitude: crosshair.latitude, longitude: crosshair.longitude)
        )
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
        if store.tool == .playCircle && store.editor.hasPendingPlayCircleCenter {
            return "Center set. Pan outward and drop a point to set the radius."
        }
        if store.tool == .playCircle, let circle = store.draftBoundaryCircle {
            return "Circle play area (\(Int(circle.radiusMeters.rounded())) m radius). Drop to redraw, or clear to switch to polygon."
        }
        if store.tool == .playCircle {
            return "Drop the center of your circle play area."
        }
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
        if store.tool == .playArea && store.draftBoundaryCircle != nil {
            return "This arena uses a circle play area. Clear it first to draw a polygon."
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
        if store.tool == .playArea && store.editor.boundaryCircle == nil && store.editor.boundary.vertices.count >= 3 {
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
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(HuntColor.muted)
        }
    }

    private func editorTool(from tool: ArenaTool) -> EditorTool {
        switch tool {
        case .playArea: .playArea
        case .playCircle: .playCircle
        case .safe: .safeCircle
        case .outOfBounds: .outOfBounds
        case .spawn: .seekerSpawn
        }
    }
}

/// Zone list that used to sit under the map. Rename, delete, and jump back to a shape.
private struct ZoneLayersSheet: View {
    @Environment(AppStore.self) private var store
    var dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.editor.zones.isEmpty {
                    Text("No zones yet. Drop an out, spawn, or safe shape on the map.")
                        .foregroundStyle(HuntColor.muted)
                        .listRowBackground(HuntColor.ink)
                }
                ForEach(store.editor.zones) { zone in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(zoneKindTitle(zone.kind))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HuntColor.muted)
                        TextField(
                            "Zone name",
                            text: Binding(
                                get: { zone.name },
                                set: { store.renameZone(id: zone.id, to: $0) }
                            )
                        )
                        .foregroundStyle(HuntColor.paper)
                        HStack {
                            if case .polygon = zone.shape {
                                Button("Edit shape") {
                                    store.editZoneShape(id: zone.id)
                                    dismiss()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HuntColor.signal)
                            }
                            Spacer()
                            Button("Delete") { store.deleteZone(id: zone.id) }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HuntColor.warning)
                        }
                    }
                    .listRowBackground(HuntColor.inkRaised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HuntColor.ink)
            .navigationTitle("Zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
    }

    private func zoneKindTitle(_ kind: ZoneKind) -> String {
        switch kind {
        case .safe: return "Safe"
        case .outOfBounds: return "Out of bounds"
        case .seekerSpawn: return "Seeker spawn"
        }
    }
}
