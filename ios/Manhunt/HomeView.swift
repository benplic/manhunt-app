import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var scanningInvite = false

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
                        HuntButton(title: "Scan invite QR", systemImage: "qrcode.viewfinder", tint: HuntColor.paper) {
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
                    Button {
                        store.editArena(arena.id.uuidString)
                    } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(arena.name)
                                        .font(.headline)
                                        .foregroundStyle(HuntColor.paper)
                                    Text("\(arena.zones.count) zones")
                                        .font(.subheadline)
                                        .foregroundStyle(HuntColor.muted)
                                }
                                Spacer()
                                Image(systemName: "map")
                                    .foregroundStyle(HuntColor.signal)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(HuntColor.muted)
    }
}
