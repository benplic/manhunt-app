import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var scanningInvite = false
    @State private var renamingArenaID: UUID?
    @State private var renameArenaDraft = ""
    @State private var deletingArenaID: UUID?

    var body: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(HuntColor.signal)
                        Text(store.displayName)
                            .font(HuntFont.title(36))
                            .foregroundStyle(HuntColor.paper)
                    }
                    Spacer()
                    Button("Sign out", action: store.signOut)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HuntColor.muted)
                }

                HuntButton(title: "New game", systemImage: "plus", action: store.openCreate)
                    .accessibilityIdentifier("new-game")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Join with a code")
                            .font(.headline)
                            .foregroundStyle(HuntColor.paper)
                        TextField("PARK42", text: $store.joinDraft)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HuntColor.paper)
                            .padding(12)
                            .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onChange(of: store.joinDraft) { _, newValue in
                                let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                                if cleaned != newValue { store.joinDraft = cleaned }
                            }
                            .accessibilityIdentifier("join-code")
                        if let joinMessage = store.joinMessage {
                            Text(joinMessage)
                                .font(.footnote)
                                .foregroundStyle(HuntColor.warning)
                        }
                        HuntButton(title: "Join", tint: HuntColor.paper, action: store.join)
                            .accessibilityIdentifier("join-game")
                        HuntButton(
                            title: "Scan invite QR",
                            systemImage: "qrcode.viewfinder",
                            tint: HuntColor.paper,
                            haptic: .light
                        ) {
                            scanningInvite = true
                        }
                        .accessibilityIdentifier("scan-invite")
                        Text("Try PARK42 to open the sample lobby.")
                            .font(.footnote)
                            .foregroundStyle(HuntColor.muted)
                    }
                }

                if let note = store.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.signal)
                }

                sectionTitle("Arenas")
                ForEach(store.arenas) { arena in
                    Card {
                        HStack {
                            Button {
                                store.editArena(arena.id.uuidString)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(arena.name)
                                        .font(.headline)
                                        .foregroundStyle(HuntColor.paper)
                                    Text("\(arena.zones.count) zones")
                                        .font(.subheadline)
                                        .foregroundStyle(HuntColor.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.huntPress(.light))
                            Button("Rename") {
                                renameArenaDraft = arena.name
                                renamingArenaID = arena.id
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HuntColor.signal)
                            Button("Delete") {
                                deletingArenaID = arena.id
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HuntColor.warning)
                        }
                    }
                }
                Button("New arena", action: store.beginNewArena)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HuntColor.signal)
                    .accessibilityIdentifier("new-arena")

                sectionTitle("Presets")
                Button(action: store.openPreset) {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Classic Manhunt")
                                    .font(.headline)
                                    .foregroundStyle(HuntColor.paper)
                                Text("Roles, head start, reveals, tags, zones, safety.")
                                    .font(.subheadline)
                                    .foregroundStyle(HuntColor.muted)
                            }
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(HuntColor.signal)
                        }
                    }
                }
                .buttonStyle(.huntPress(.light))
                .accessibilityIdentifier("edit-preset")
            }
            .padding(20)
        }
        .background(HuntColor.ink)
        .sheet(isPresented: $scanningInvite) {
            QRScannerView { payload in
                scanningInvite = false
                store.openInvite(payload)
            }
            .ignoresSafeArea()
        }
        .alert("Rename arena", isPresented: Binding(
            get: { renamingArenaID != nil },
            set: { if !$0 { renamingArenaID = nil } }
        )) {
            TextField("Name", text: $renameArenaDraft)
            Button("Save") {
                if let id = renamingArenaID {
                    store.renameArena(id: id, to: renameArenaDraft)
                }
                renamingArenaID = nil
            }
            Button("Cancel", role: .cancel) { renamingArenaID = nil }
        }
        .alert("Delete this arena?", isPresented: Binding(
            get: { deletingArenaID != nil },
            set: { if !$0 { deletingArenaID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = deletingArenaID {
                    store.deleteArena(id: id)
                }
                deletingArenaID = nil
            }
            Button("Cancel", role: .cancel) { deletingArenaID = nil }
        } message: {
            Text("Games already started keep their saved snapshot.")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(HuntColor.muted)
    }
}
