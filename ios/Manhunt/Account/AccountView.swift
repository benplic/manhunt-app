import SwiftUI

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = AppStore.privacyPolicyURL() {
                        Link(destination: url) {
                            accountRow(title: "Privacy policy", systemImage: "hand.raised")
                        }
                        .accessibilityIdentifier("account-privacy-link")
                    }

                    if let url = AppStore.supportMailURL() {
                        Link(destination: url) {
                            accountRow(title: "Email support", systemImage: "envelope")
                        }
                        .accessibilityIdentifier("account-support-link")
                    }

                    blockedPlayersSection

                    Text("Deleting your account removes your profile and sign-in tokens from the server. Past hunts may show an anonymized name.")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        accountRow(title: "Delete account", systemImage: "trash", tint: HuntColor.warning)
                    }
                    .accessibilityIdentifier("account-delete")
                }
                .padding(20)
            }
            .background(HuntColor.ink)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Delete account", role: .destructive) {
                    Task {
                        await store.deleteAccount()
                        if store.session == nil {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. You will be signed out immediately.")
            }
        }
    }

    @ViewBuilder
    private var blockedPlayersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blocked players")
                .font(.caption.weight(.bold))
                .foregroundStyle(HuntColor.muted)
                .accessibilityIdentifier("account-blocked-heading")

            let blocked = store.blockedPlayers
            if blocked.isEmpty {
                Text("No blocked players.")
                    .font(.footnote)
                    .foregroundStyle(HuntColor.muted)
                    .accessibilityIdentifier("account-blocked-empty")
            } else {
                ForEach(blocked) { entry in
                    Card {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.anonymizedBlockedName(for: entry.playerId) ?? "Blocked Player")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(HuntColor.paper)
                                Text("Was: \(entry.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(HuntColor.muted)
                            }
                            Spacer()
                            Button("Unblock") {
                                store.unblockPlayer(entry.playerId)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HuntColor.signal)
                            .accessibilityIdentifier("account-unblock-\(entry.playerId)")
                        }
                    }
                }
            }
        }
    }

    private func accountRow(title: String, systemImage: String, tint: Color = HuntColor.paper) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(HuntColor.signal)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HuntColor.muted)
            }
        }
    }
}

#if DEBUG
#Preview {
    AccountView()
        .environment(AppStore.makePreview())
}
#endif
