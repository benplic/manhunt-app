import SwiftUI

/// Host-only controls for steering the PARK42 demo lobby and bots.
struct DemoPanelView: View {
    @Environment(AppStore.self) private var store
    var dismiss: () -> Void

    private let speeds = [1, 2, 5, 10]

    var body: some View {
        let snapshot = store.match?.snapshot
        let demo = snapshot?.demo
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SIMULATION SPEED")
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(HuntColor.muted)
                            HStack(spacing: 8) {
                                ForEach(speeds, id: \.self) { speed in
                                    let selected = (demo?.speed ?? 1) == speed
                                    Button {
                                        store.setDemoSpeed(speed)
                                    } label: {
                                        Text("\(speed)x")
                                            .font(.subheadline.weight(.bold))
                                            .monospacedDigit()
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(
                                                selected ? HuntColor.signal : HuntColor.ink,
                                                in: Capsule()
                                            )
                                            .foregroundStyle(selected ? HuntColor.ink : HuntColor.paper)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("demo-speed-\(speed)")
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PHASE & ACTIONS")
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(HuntColor.muted)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                actionPill("Skip 1 min", systemImage: "forward.fill", tint: HuntColor.paper) {
                                    store.demoSkipMinute()
                                }
                                .accessibilityIdentifier("demo-skip")

                                actionPill(endPhaseLabel(for: snapshot?.phase), systemImage: "flag.checkered", tint: HuntColor.signal) {
                                    store.demoEndPhase()
                                }
                                .accessibilityIdentifier("demo-end-phase")

                                actionPill("Move me", systemImage: "figure.walk", tint: HuntColor.safe) {
                                    dismiss()
                                    store.beginDemoMovePick()
                                }
                                .accessibilityIdentifier("demo-move-me")

                                actionPill("Switch team", systemImage: "arrow.left.arrow.right", tint: HuntColor.paper) {
                                    store.demoSwitchTeam()
                                }
                                .accessibilityIdentifier("demo-switch-team")

                                actionPill("Force tag", systemImage: "scope", tint: HuntColor.seeker) {
                                    store.demoForceTag()
                                }
                                .accessibilityIdentifier("demo-force-tag")

                                actionPill("Force reveal", systemImage: "dot.radiowaves.left.and.right", tint: HuntColor.warning) {
                                    store.demoForceReveal()
                                }
                                .accessibilityIdentifier("demo-force-reveal")

                                actionPill("+100 pts", systemImage: "plus.circle.fill", tint: HuntColor.hider) {
                                    store.demoAddPoints(100)
                                }
                                .accessibilityIdentifier("demo-add-points")
                            }
                        }
                    }

                    if let bots = demo?.bots, !bots.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("BOTS")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(HuntColor.muted)

                                ForEach(bots) { bot in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text(bot.displayName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(HuntColor.paper)
                                                RolePill(role: visualRole(for: bot.role))
                                            }
                                            Text(botStatusLine(bot))
                                                .font(.caption)
                                                .foregroundStyle(HuntColor.muted)
                                        }
                                        Spacer()
                                        let isDark = bot.mode == "go_dark" || bot.status == .signalLost
                                        botCircleButton(
                                            systemImage: isDark ? "antenna.radiowaves.left.and.right" : "wifi.slash",
                                            tint: isDark ? HuntColor.signal : HuntColor.warning,
                                            label: isDark ? "Restore \(bot.displayName)" : "Go dark \(bot.displayName)"
                                        ) {
                                            store.demoToggleBotDark(botID: bot.playerId, dark: !isDark)
                                        }

                                        let isOOB = bot.mode == "oob"
                                        botCircleButton(
                                            systemImage: isOOB ? "arrow.uturn.backward" : "figure.walk.departure",
                                            tint: isOOB ? HuntColor.safe : HuntColor.seeker,
                                            label: isOOB ? "Return \(bot.displayName)" : "Send OOB \(bot.displayName)"
                                        ) {
                                            store.demoToggleBotOOB(botID: bot.playerId, oob: !isOOB)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(HuntColor.ink)
            .navigationTitle("Demo controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func actionPill(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background(HuntColor.ink, in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.65), lineWidth: 1))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func botCircleButton(
        systemImage: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(HuntColor.ink, in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.65), lineWidth: 1))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func endPhaseLabel(for phase: MatchPhase?) -> String {
        switch phase {
        case .lobby: return "Start now"
        case .headStart: return "End head start"
        default: return "End hunt"
        }
    }

    private func botStatusLine(_ bot: DemoBotDTO) -> String {
        if bot.status == .eliminated { return "Tagged out" }
        if bot.mode == "go_dark" || bot.status == .signalLost { return "Signal lost" }
        if bot.mode == "oob" { return "Out of bounds" }
        return "Active"
    }

    private func visualRole(for role: PlayerRole) -> VisualRole {
        switch role {
        case .hider: return .hider
        case .seeker: return .seeker
        case .unassigned: return .unassigned
        }
    }
}
