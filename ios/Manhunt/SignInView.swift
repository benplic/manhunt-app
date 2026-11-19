import SwiftUI

struct SignInView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case displayName
        case serverURL
        case homeKey
    }

    private let ageChoices = Array(13...99)

    var body: some View {
        @Bindable var store = store
        return ZStack(alignment: .bottom) {
            TopoField()
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer(minLength: 40)
                    Text("Manhunt")
                        .font(HuntFont.wordmark(68))
                        .foregroundStyle(HuntColor.paper)
                    Text("with friends")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(HuntColor.signal)
                    VStack(alignment: .leading, spacing: 8) {
                        rule("Hiders run. Seekers hunt.")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Display name")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HuntColor.muted)
                        TextField("Casey Lee", text: $store.displayName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .displayName)
                            .padding(12)
                            .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(HuntColor.paper)
                            .accessibilityIdentifier("display-name")

                        Text("Age")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HuntColor.muted)
                        Picker("Age", selection: ageSelection) {
                            ForEach(ageChoices, id: \.self) { age in
                                Text("\(age)").tag(age)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("sign-in-age")

                        #if DEBUG
                        Text("Server URL")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HuntColor.muted)
                        TextField("http://localhost:8000", text: $store.serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .serverURL)
                            .padding(12)
                            .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(HuntColor.paper)
                            .accessibilityIdentifier("server-url")
                        #endif

                        Text("Home key")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HuntColor.muted)
                        SecureField("From the home server .env", text: $store.devAuthSecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .homeKey)
                            .padding(12)
                            .background(HuntColor.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(HuntColor.paper)
                            .accessibilityIdentifier("dev-auth-secret")
                    }

                    if let url = AppStore.privacyPolicyURL() {
                        Link("Privacy policy", destination: url)
                            .font(.footnote)
                            .foregroundStyle(HuntColor.signal)
                            .accessibilityIdentifier("privacy-policy-link")
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
                    .buttonStyle(.huntPress(.medium))
                    .accessibilityIdentifier("sign-in")
                    Text("Precise location stays on during a game. Manhunt does not ask for Always.")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if Int(store.ageYears).flatMap({ ageChoices.contains($0) ? $0 : nil }) == nil {
                store.ageYears = "18"
            }
        }
    }

    private var ageSelection: Binding<Int> {
        Binding(
            get: {
                let parsed = Int(store.ageYears.trimmingCharacters(in: .whitespacesAndNewlines))
                if let parsed, ageChoices.contains(parsed) { return parsed }
                return 18
            },
            set: { store.ageYears = String($0) }
        )
    }

    private func rule(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(HuntColor.paper.opacity(0.92))
    }
}
