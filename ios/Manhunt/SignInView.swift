import SwiftUI

struct SignInView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return ZStack(alignment: .bottom) {
            TopoField()
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                Text("FIELD GAME")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(HuntColor.signal)
                Text("Manhunt")
                    .font(HuntFont.wordmark(68))
                    .foregroundStyle(HuntColor.paper)
                VStack(alignment: .leading, spacing: 8) {
                    rule("The host draws the park.")
                    rule("Hiders run. Seekers hunt.")
                    rule("The phone only keeps score.")
                }
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Display name")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HuntColor.muted)
                    TextField("Casey Lee", text: $store.displayName)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(HuntColor.paper)
                        .accessibilityIdentifier("display-name")
                    Text("Server URL")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HuntColor.muted)
                    TextField("http://localhost:8000", text: $store.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(HuntColor.paper)
                        .accessibilityIdentifier("server-url")
                }

                if let note = store.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                }

                Button(action: store.signIn) {
                    Text("Play")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sign-in")
                Text("Precise location stays on during a game. Manhunt does not ask for Always. Sign in with Apple arrives in Phase 2.")
                    .font(.footnote)
                    .foregroundStyle(HuntColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
    }

    private func rule(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(HuntColor.paper.opacity(0.92))
    }
}
