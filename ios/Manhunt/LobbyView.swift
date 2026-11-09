import SwiftUI

struct LobbyView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: store.isHost ? "Your lobby" : "Joined",
                    subtitle: store.isHost ? "Share the code, then set roles." : "Waiting for the host to start.",
                    onBack: store.goHome
                )

                CodeReadout(code: store.joinCode)
                    .frame(maxWidth: .infinity)

                HStack {
                    Label("\(store.players.count) players", systemImage: "person.2")
                    Spacer()
                    Text(store.isHost ? "You are hosting" : "\(store.hostName) is hosting")
                }
                .font(.subheadline)
                .foregroundStyle(HuntColor.muted)

                VStack(spacing: 10) {
                    ForEach(store.players) { player in
                        Button {
                            guard store.isHost else { return }
                            store.cycleRole(player.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(player.role.tint)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.isYou ? "\(player.name) (you)" : player.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(HuntColor.paper)
                                    if player.isHost {
                                        Text("Host")
                                            .font(.caption)
                                            .foregroundStyle(HuntColor.muted)
                                    }
                                }
                                Spacer()
                                RolePill(role: player.role)
                            }
                            .padding(14)
                            .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(player.name), \(player.role.rawValue)")
                    }
                }

                if store.isHost {
                    Stepper(value: $store.hiderCount, in: 1...max(1, store.players.count - 1)) {
                        Text("Hiders \(store.hiderCount)")
                            .foregroundStyle(HuntColor.paper)
                    }
                    .padding(.horizontal, 4)

                    HuntButton(title: "Randomize roles", systemImage: "shuffle", tint: HuntColor.paper, action: store.randomizeRoles)
                    HuntButton(title: "Start hunt", systemImage: "flag.checkered", action: store.startLive)
                        .accessibilityIdentifier("start-hunt")
                    Text("Tap a player to cycle Hider, Seeker, and Open. Randomize uses the hider count above.")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                }
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }
}
