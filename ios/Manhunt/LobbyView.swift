import SwiftUI

struct LobbyView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var confirmLeave = false
    @State private var pendingBlock: PendingBlock?
    @State private var editing: LobbyEditKind?

    var body: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: store.isHost ? "Your lobby" : "Joined",
                    subtitle: store.isHost ? "Share the code, then set roles." : "Waiting for the host to start.",
                    onBack: { confirmLeave = true }
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

                // Everyone sees the live play-area size. Only the host gets the edit buttons.
                if let radius = store.match?.snapshot.arena?.boundaryCircle?.radiusMeters {
                    Text("Play area: \(Int(radius.rounded())) m radius")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                        .accessibilityIdentifier("lobby-radius-summary")
                }

                if store.isHost {
                    HStack(spacing: 8) {
                        HuntButton(
                            title: "Edit rules",
                            systemImage: "slider.horizontal.3",
                            tint: HuntColor.paper,
                            haptic: .light
                        ) { editing = .rules }
                            .accessibilityIdentifier("lobby-edit-rules")
                        // A polygon arena has no radius to edit, and the server would replace it.
                        if store.match?.snapshot.arena?.boundaryCircle != nil {
                        HuntButton(
                            title: "Edit map",
                            systemImage: "map",
                            tint: HuntColor.paper,
                            haptic: .light
                        ) { editing = .map }
                            .accessibilityIdentifier("lobby-edit-map")
                        }
                    }
                }

                VStack(spacing: 10) {
                    ForEach(store.players) { player in
                        HStack(spacing: 8) {
                            Button {
                                guard store.isHost else { return }
                                store.cycleRole(player.id)
                            } label: {
                                HStack(spacing: 12) {
                                    PlayerAvatar(name: player.name, playerID: player.id, size: 28)
                                    HStack(spacing: 6) {
                                        Text(player.isYou ? "\(player.name) (you)" : player.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(HuntColor.paper)
                                        if player.isHost {
                                            Image(systemName: "crown.fill")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(HuntColor.signal)
                                                .accessibilityLabel("Host")
                                        }
                                    }
                                    Spacer()
                                    RolePill(role: player.role)
                                }
                                .padding(14)
                                .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.huntPress(.light))
                            .accessibilityLabel("\(player.name), \(player.role.rawValue)")
                            .contextMenu {
                                if !player.isYou {
                                    if let url = store.reportMailURL(playerID: player.id, displayName: player.name) {
                                        Button("Report") { openURL(url) }
                                    }
                                    Button("Block", role: .destructive) {
                                        pendingBlock = PendingBlock(id: player.id, name: player.name)
                                    }
                                }
                            }

                            if store.isHost, !player.isYou, !player.isHost {
                                Button {
                                    store.removeLobbyPlayer(player.id)
                                } label: {
                                    Image(systemName: "person.badge.minus")
                                        .foregroundStyle(HuntColor.warning)
                                        .frame(width: 44, height: 44)
                                        .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.huntPress(.warning))
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
                                    tint: HuntColor.paper,
                                    haptic: .light
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
                                                .animation(.snappy, value: selected)
                                        }
                                        .buttonStyle(.huntPress(.selection))
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
                                                .animation(.snappy, value: selected)
                                        }
                                        .buttonStyle(.huntPress(.selection))
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

                    HuntButton(
                        title: "Randomize roles",
                        systemImage: "shuffle",
                        tint: HuntColor.paper,
                        haptic: .light,
                        action: store.randomizeRoles
                    )
                    HuntButton(title: "Start hunt", systemImage: "flag.checkered", action: store.startLive)
                        .accessibilityIdentifier("start-hunt")
                    Text("Tap a player to cycle Hider and Seeker. Randomize uses the seeker count above. Everyone else hides.")
                        .font(.footnote)
                        .foregroundStyle(HuntColor.muted)
                }
            }
            .padding(20)
        }
        .background(HuntColor.ink)
        .sheet(item: $editing) { kind in
            LobbyEditSheet(
                kind: kind,
                timers: store.match?.snapshot.timers,
                radiusM: store.match?.snapshot.arena?.boundaryCircle?.radiusMeters
            ) { editing = nil }
                .presentationDetents([.medium])
        }
        .alert("Leave this hunt?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive, action: store.goHome)
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Block this player?",
            isPresented: Binding(
                get: { pendingBlock != nil },
                set: { if !$0 { pendingBlock = nil } }
            )
        ) {
            Button("Block", role: .destructive) {
                if let pendingBlock {
                    store.blockPlayer(pendingBlock.id, displayName: pendingBlock.name)
                }
                pendingBlock = nil
            }
            Button("Cancel", role: .cancel) { pendingBlock = nil }
        } message: {
            Text("Their pin stays on the map as “Blocked Player #…”. You can unblock them in Account.")
        }
    }
}
