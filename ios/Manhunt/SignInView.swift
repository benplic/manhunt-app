import SwiftUI

struct SignInView: View {
    @Environment(VisualStore.self) private var store

    var body: some View {
        ZStack(alignment: .bottom) {
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
                .padding(.bottom, 12)
                Button(action: store.signIn) {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sign-in")
                Text("Precise location stays on during a game. Manhunt does not ask for Always.")
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
