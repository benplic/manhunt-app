import SwiftUI

struct LiveGameView: View {
    @Environment(VisualStore.self) private var store
    @State private var showCode = false
    @State private var showHost = false

    var body: some View {
        @Bindable var store = store
        let youAreHider = store.viewingRole == .hider
        return ZStack(alignment: .top) {
            HuntMap(
                boundary: store.arena.boundary,
                zones: store.arena.zones,
                people: store.players,
                showHiders: youAreHider ? false : store.situation != .headStart,
                showSeekers: youAreHider ? store.radarOn : true,
                fuzzyHiders: store.situation != .signalLost,
                region: store.arena.region,
                onDrop: nil
            )
            .ignoresSafeArea()

            if store.situation == .headStart && !youAreHider {
                HuntColor.ink.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text("MAP LOCKED")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                    Text("Seekers wait here.")
                        .font(HuntFont.title(28))
                    Text("Hiders still have 0:42.")
                        .foregroundStyle(HuntColor.muted)
                }
                .foregroundStyle(HuntColor.paper)
            }

            VStack(spacing: 10) {
                topBar
                if store.situation == .reconnecting {
                    banner(title: "Reconnecting", detail: "The last event will catch up when the socket returns.", tint: HuntColor.paper)
                }
                if store.situation == .outOfBounds {
                    banner(title: "Out of bounds · 0:12", detail: "Get back inside the yellow line before the penalty.", tint: HuntColor.warning)
                }
                if store.situation == .signalLost {
                    banner(title: "Sam went dark", detail: "Last precise fix is on the map for everyone. Safety overrides the hunt.", tint: HuntColor.danger)
                }
                if store.paused {
                    banner(title: "Paused", detail: "The host stopped the clock.", tint: HuntColor.paper)
                }
                if let note = store.note {
                    Text(note)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: Capsule())
                        .foregroundStyle(HuntColor.paper)
                }
                Spacer()
                dock(youAreHider: youAreHider)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showCode) {
            TagCodeSheet()
                .presentationDetents([.medium])
        }
        .confirmationDialog("Host", isPresented: $showHost, titleVisibility: .visible) {
            Button(store.paused ? "Resume" : "Pause") { store.paused.toggle() }
            Button("Remove Sam from the preview") {
                store.players.removeAll { $0.id == "sam" }
            }
            Button("End game", role: .destructive, action: store.endLive)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: store.goHome) {
                Image(systemName: "xmark")
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close map")
            VStack(alignment: .leading, spacing: 0) {
                Text(store.paused ? "Paused" : store.situation.rawValue)
                    .font(.headline)
                Text(store.viewingRole == .hider ? "You are hiding" : "You are seeking")
                    .font(.caption)
                    .foregroundStyle(HuntColor.muted)
            }
            Spacer()
            Menu {
                Picker("See the game as", selection: Bindable(store).viewingRole) {
                    Text("Seeker").tag(VisualRole.seeker)
                    Text("Hider").tag(VisualRole.hider)
                }
                Picker("Situation", selection: Bindable(store).situation) {
                    ForEach(LiveSituation.allCases) { situation in
                        Text(situation.rawValue).tag(situation)
                    }
                }
            } label: {
                Image(systemName: "eye")
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Preview role and situation")
            if store.isHost {
                Button {
                    showHost = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Host controls")
            }
        }
        .foregroundStyle(HuntColor.paper)
    }

    private func dock(youAreHider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.shownPoints) pts")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(youAreHider ? "Warmth is hidden from you." : "Riley is warm · about 60 m")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                }
                Spacer()
                if !youAreHider {
                    Image(systemName: "location.north.fill")
                        .font(.title2)
                        .rotationEffect(.degrees(28))
                        .foregroundStyle(HuntColor.signal)
                }
            }
            if !youAreHider && store.situation != .headStart {
                HStack {
                    proximity("Riley", "18 m")
                    proximity("Quinn", "46 m")
                    proximity("Sam", "90 m")
                }
                Button(action: {}) {
                    Text("Tag")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(HuntColor.seeker, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(HuntColor.paper)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag")
                Text("Tag sends a claim. Both phones have to agree you are inside 2 m, and a safe zone or shield blocks it.")
                    .font(.caption2)
                    .foregroundStyle(HuntColor.muted)
            }
            if youAreHider {
                Button {
                    showCode = true
                } label: {
                    Label("Show tag code", systemImage: "qrcode")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(HuntColor.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(HuntColor.ink)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SamplePark.powerUps.filter { $0.role == store.viewingRole }) { chip in
                        let armed = store.armedPowerUps.contains(chip.id)
                        Button {
                            store.togglePower(chip)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chip.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(armed ? "Armed" : "\(chip.cost) pts")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(armed ? HuntColor.signal : HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(armed ? HuntColor.ink : HuntColor.paper)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .colorScheme(.dark)
    }

    private func proximity(_ name: String, _ distance: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.weight(.semibold))
            Text(distance).font(.caption2).foregroundStyle(HuntColor.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(HuntColor.ink.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func banner(title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(HuntColor.paper.opacity(0.85))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HuntColor.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(HuntColor.paper)
    }
}

private struct TagCodeSheet: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Tag code")
                .font(HuntFont.title(28))
            SampleCodeMark()
                .frame(width: 220, height: 220)
            Text("This mark stands in for a code the server signs and rotates every 30 seconds. A seeker scans it when Ultra Wideband is not available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

private struct SampleCodeMark: View {
    var body: some View {
        Canvas { context, size in
            let cells = 21
            let cell = size.width / CGFloat(cells)
            for row in 0..<cells {
                for column in 0..<cells {
                    let on = isFinder(row: row, column: column) || ((row * 7 + column * 3) % 5 == 0)
                    if on {
                        let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell - 0.4, height: cell - 0.4)
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
            }
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func isFinder(row: Int, column: Int) -> Bool {
        let corners = [(1, 1), (1, 13), (13, 1)]
        for (originRow, originColumn) in corners {
            let dr = row - originRow
            let dc = column - originColumn
            if (0...6).contains(dr), (0...6).contains(dc) {
                let edge = dr == 0 || dr == 6 || dc == 0 || dc == 6
                let core = (2...4).contains(dr) && (2...4).contains(dc)
                if edge || core { return true }
            }
        }
        return false
    }
}
