import SwiftUI

struct LiveGameView: View {
    @Environment(AppStore.self) private var store
    @State private var showCode = false
    @State private var showHost = false
    @State private var showScanner = false

    var body: some View {
        @Bindable var store = store
        let youAreHider = store.viewingRole == .hider
        let snapshot = store.match?.snapshot
        let chrome = HeadStartChrome.kind(
            phase: snapshot?.phase ?? .active,
            role: snapshot?.you.role ?? .unassigned,
            seekerLock: snapshot?.seekerLock
        )
        let spawnZones = snapshot?.spawnLock?.zones.map { $0.asVisual() } ?? []
        let known = Set(store.liveZones.map(\.id))
        let zones = store.liveZones + spawnZones.filter { !known.contains($0.id) }
        return ZStack(alignment: .top) {
            HuntMap(
                boundary: store.arena.boundary,
                zones: zones,
                people: store.livePeople,
                showHiders: true,
                showSeekers: youAreHider ? store.radarShowsSeekers : true,
                fuzzyHiders: false,
                region: store.arena.region,
                onDrop: store.decoyPicking ? { store.dropDecoy(at: $0) } : nil,
                emphasizeSpawn: chrome == .spawnZone
            )
            .ignoresSafeArea()

            if chrome == .fullMap {
                HuntColor.ink.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text("MAP LOCKED")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                    Text("Seekers wait here.")
                        .font(HuntFont.title(28))
                    if let remaining = store.match?.snapshot.phaseRemainingS {
                        Text("Hiders still have \(clock(remaining)).")
                            .foregroundStyle(HuntColor.muted)
                    }
                }
                .foregroundStyle(HuntColor.paper)
            }

            VStack(spacing: 10) {
                topBar
                if store.locationAccuracy == .denied || store.locationAccuracy == .reduced {
                    locationBlock
                }
                ForEach(store.match?.snapshot.banners ?? []) { banner in
                    self.banner(title: banner.title, detail: banner.detail, tint: tone(banner.tone))
                }
                if store.situation == .reconnecting {
                    banner(title: "Reconnecting", detail: "The last event will catch up when the socket returns.", tint: HuntColor.paper)
                }
                if store.situation == .outOfBounds {
                    let remaining = store.match?.snapshot.you.bounds.remainingS
                    banner(
                        title: remaining.map { "Out of bounds · \(clock($0))" } ?? "Out of bounds",
                        detail: "Get back inside the yellow line before the penalty.",
                        tint: HuntColor.warning
                    )
                }
                if store.paused {
                    banner(title: "Paused", detail: "The host stopped the clock.", tint: HuntColor.paper)
                }
                if store.decoyPicking {
                    HStack(spacing: 10) {
                        Text("Drop a decoy inside the yellow line.")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Button("Cancel") { store.cancelDecoyPick() }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(HuntColor.paper)
                } else if let note = store.note {
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
            TagCodeSheet(token: store.match?.qrToken ?? "manhunt-preview")
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showScanner) {
            VStack {
                QRScannerView { token in
                    store.submitQR(token)
                    showScanner = false
                }
                .ignoresSafeArea()
                #if DEBUG
                TextField("Paste token", text: $store.pasteToken)
                    .textInputAutocapitalization(.never)
                    .padding(12)
                Button("Submit token") {
                    store.submitQR(store.pasteToken)
                    showScanner = false
                }
                .padding(.bottom, 12)
                #endif
            }
            .background(HuntColor.ink)
        }
        .confirmationDialog("Host", isPresented: $showHost, titleVisibility: .visible) {
            Button(store.paused ? "Resume" : "Pause", action: store.pauseOrResume)
            Button("End game", role: .destructive, action: store.endLive)
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.situation) { _, situation in
            if situation == .outOfBounds {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
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

    private var locationBlock: some View {
        banner(
            title: store.locationAccuracy == .denied ? "Location is off" : "Precise location is off",
            detail: "Allow precise location while you play. Manhunt never asks for Always.",
            tint: HuntColor.danger,
            actionTitle: "Open Settings",
            action: { AppSettings.open() }
        )
    }

    private func dock(youAreHider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.shownPoints) pts")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(HintCopy.line(
                        role: store.match?.snapshot.you.role ?? .unassigned,
                        hint: store.match?.snapshot.you.hint
                    ))
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                }
                Spacer()
            }
            if !youAreHider && store.situation != .headStart {
                if store.match?.snapshot.tagMethod == "uwb" {
                    uwbTags
                } else {
                    Button {
                        showScanner = true
                    } label: {
                        Text("Scan tag")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(HuntColor.seeker, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(HuntColor.paper)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tag")
                    Text("Scan the hider's rotating code. Both phones have to be within pairing range.")
                        .font(.caption2)
                        .foregroundStyle(HuntColor.muted)
                }
                if let tagMessage = store.tagMessage {
                    Text(tagMessage)
                        .font(.caption)
                        .foregroundStyle(HuntColor.warning)
                }
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
                        let enabled = store.chipIsTappable(chip)
                        let cooling = store.match?.snapshot.you.cooldowns?[chip.id] ?? 0
                        Button {
                            store.buyPower(chip)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chip.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(cooling > 0 ? "\(cooling)s" : "\(chip.cost) pts")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                enabled ? HuntColor.ink : HuntColor.ink.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .foregroundStyle(enabled ? HuntColor.paper : HuntColor.paper.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .colorScheme(.dark)
    }

    /// TODO: spec section 5.6 lets a failed UWB range fall back to QR. This slice does not.
    /// `method: uwb` rejects a QR-only claim.
    private var uwbTags: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.uwbPeers.isEmpty {
                Text("No hider in Ultra Wideband range.")
                    .font(.caption)
                    .foregroundStyle(HuntColor.muted)
            }
            ForEach(store.uwbPeers) { peer in
                Button {
                    store.claimUWB(hiderID: peer.id)
                } label: {
                    let distance = store.uwbDistance[peer.id].map { String(format: "%.1f m", $0) }
                    Text(distance.map { "Tag \(peer.name) · \($0)" } ?? "Tag \(peer.name)")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(HuntColor.seeker, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(HuntColor.paper)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag")
            }
        }
    }

    private func banner(
        title: String,
        detail: String,
        tint: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(detail).font(.caption).foregroundStyle(HuntColor.paper.opacity(0.85))
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("open-settings")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HuntColor.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(HuntColor.paper)
    }

    private func tone(_ raw: String) -> Color {
        switch raw {
        case "warning": return HuntColor.warning
        case "safety", "danger": return HuntColor.danger
        case "success": return HuntColor.signal
        default: return HuntColor.paper
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

}

private struct TagCodeSheet: View {
    var token: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Tag code")
                .font(HuntFont.title(28))
            QRCodeView(token: token)
                .frame(width: 220, height: 220)
            Text("This code rotates about every 30 seconds. A seeker scans it when Ultra Wideband is not available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
