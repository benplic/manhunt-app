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
                    dismiss()
                    store.deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. You will be signed out immediately.")
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