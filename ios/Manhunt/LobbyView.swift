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

                if let inviteURL = store.inviteURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(HuntColor.muted)
                        QRCodeView(token: inviteURL.absoluteString)
                            .frame(width: 180, height: 180)
                        Text(inviteURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(HuntColor.paper)
                            .textSelection(.enabled)
                    }
                }

                HStack {
                    Label("\(store.players.count) players", systemImage: "person.2")
                    Spacer()
                    Text(store.isHost ? "You are hosting" : "\(store.hostName) is hosting")
                }
                .font(.subheadline)
                .foregroundStyle(HuntColor.muted)

                if let timers = store.match?.snapshot.timers {
                    Text(RulesSummary.line(timers: timers))
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                }

                VStack(spacing: 10) {
                    ForEach(store.players) { player in
                        HStack(spacing: 8) {
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

                            if store.isHost, !player.isYou, !player.isHost {
                                Button {
                                    store.removeLobbyPlayer(player.id)
                                } label: {
                                    Image(systemName: "person.badge.minus")
                                        .foregroundStyle(HuntColor.warning)
                                        .frame(width: 44, height: 44)
                                        .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(player.name)")
                            }
                        }
                    }
                }

                if let demo = store.match?.snapshot.demo, demo.controlsEnabled {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("DEMO LOBBY")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(HuntColor.signal)
                                Spacer()
                                if let seconds = store.match?.snapshot.lobbyStartsInS {
                                    Text(demo.lobbyHold ? "Held at \(seconds)s" : "Starts in \(seconds)s")
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(HuntColor.warning)
                                        .contentTransition(.numericText(countsDown: true))
                                        .animation(.snappy, value: seconds)
                                }
                            }

                            HStack(spacing: 8) {
                                HuntButton(title: "Start now", systemImage: "flag.checkered") {
                                    store.demoEndPhase()
                                }
                                .accessibilityIdentifier("demo-lobby-start")

                                HuntButton(
                                    title: demo.lobbyHold ? "Resume" : "Hold",
                                    systemImage: demo.lobbyHold ? "play.fill" : "pause.fill",
                                    tint: HuntColor.paper
                                ) {
                                    store.demoToggleLobbyHold()
                                }
                                .accessibilityIdentifier("demo-lobby-hold")
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("My team")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HuntColor.muted)
                                HStack(spacing: 8) {
                                    ForEach([PlayerRole.hider, .seeker], id: \.self) { role in
                                        let selected = store.match?.snapshot.you.role == role
                                        Button {
                                            store.demoSwitchTeam(role)
                                        } label: {
                                            Text(role == .hider ? "Hider" : "Seeker")
                                                .font(.subheadline.weight(.semibold))
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 36)
                                                .background(
                                                    selected ? (role == .hider ? HuntColor.hider : HuntColor.seeker) : HuntColor.ink,
                                                    in: Capsule()
                                                )
                                                .foregroundStyle(selected ? HuntColor.ink : HuntColor.paper)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Head start lock")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HuntColor.muted)
                                HStack(spacing: 8) {
                                    ForEach(["spawn_zone", "locked_map"], id: \.self) { mode in
                                        let selected = demo.seekerLock == mode
                                        Button {
                                            store.demoSetSeekerLock(mode)
                                        } label: {
                                            Text(mode == "spawn_zone" ? "Spawn zone" : "Locked map")
                                                .font(.subheadline.weight(.semibold))
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 36)
                                                .background(
                                                    selected ? HuntColor.signal : HuntColor.ink,
                                                    in: Capsule()
                                                )
                                                .foregroundStyle(selected ? HuntColor.ink : HuntColor.paper)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                } else if let seconds = store.match?.snapshot.lobbyStartsInS {
                    Text("Sample hunt starts in \(seconds)s. Roles are already set. End the game to open results.")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                }

                if let note = store.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(HuntColor.warning)
                        .accessibilityIdentifier("lobby-note")
                }

                if store.isHost {
                    Stepper(value: $store.seekerCount, in: 1...max(1, store.players.count - 1)) {
                        Text("Seekers \(store.seekerCount)")
                            .foregroundStyle(HuntColor.paper)
                    }
                    .padding(.horizontal, 4)

                    HuntButton(title: "Randomize roles", systemImage: "shuffle", tint: HuntColor.paper, action: store.randomizeRoles)
                    HuntButton(title: "Start hunt", systemImage: "flag.checkered", action: store.startLive)
                        .accessibilityIdentifier("start-hunt")
                    Text("Tap a player to cycle Hider, Seeker, and Open. Randomize uses the seeker count above. Everyone else hides.")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                }
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }
}
