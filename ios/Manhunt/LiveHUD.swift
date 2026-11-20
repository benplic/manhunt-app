import SwiftUI

struct LiveHUD: View {
    var snapshot: PlayerViewDTO?
    var paused: Bool
    var anchoredAt: Date
    var situation: LiveSituation

    var body: some View {
        let rate = ClockLead.rate(snapshot: snapshot, paused: paused)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: rate == 0)) { timeline in
            let lead = ClockLead.seconds(rate: rate, anchoredAt: anchoredAt, now: timeline.date)
            content(PhaseClock(snapshot: snapshot, paused: paused, leadS: lead), leadS: lead)
        }
    }

    private func content(_ clock: PhaseClock, leadS: Double) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(clock.primaryLabel)
                        .font(.caption2)
                        .foregroundStyle(HuntColor.muted)
                    Text(clock.primaryClock)
                        .font(.system(size: LiveHUDLayout.clockPointSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.2), value: clock.primaryClock)
                }
                HuntProgressBar(
                    progress: clock.primaryProgress,
                    tint: situation == .headStart ? HuntColor.signal : HuntColor.paper,
                    height: LiveHUDLayout.barHeight
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                if let pingClock = clock.pingClock {
                    Text("Ping \(pingClock)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(HuntColor.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.2), value: pingClock)
                }
                if let zoneLine = clock.zoneLine {
                    Text(zoneLine)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(clock.zoneImminent ? HuntColor.warning : HuntColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                ForEach(Self.effectLines(snapshot: snapshot, leadS: leadS)) { line in
                    Text(line.text)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(HuntColor.signal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.2), value: line.text)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HuntColor.line, lineWidth: 1)
        )
    }

    /// HUD rows for live timed effects. Shield is always shown to every role.
    static func effectLines(snapshot: PlayerViewDTO?, leadS: Double) -> [EffectHudLine] {
        guard let snapshot else { return [] }
        let youId = snapshot.you.playerId
        return (snapshot.activeEffects ?? []).compactMap { effect in
            let remaining = max(0, Int(floor(Double(effect.remainingS) - leadS)))
            guard remaining > 0 else { return nil }
            let title = effectTitle(effect.type)
            let clock = String(format: "%d:%02d", remaining / 60, remaining % 60)
            let text: String
            if effect.ownerId == youId {
                text = "\(title) \(clock)"
            } else {
                let name = effect.displayName.isEmpty ? "Player" : effect.displayName
                text = "\(title) · \(name) · \(clock)"
            }
            return EffectHudLine(id: effect.id, text: text)
        }
    }

    private static func effectTitle(_ type: String) -> String {
        switch type {
        case "shield": return "Shield"
        case "lockdown": return "Lockdown"
        case "jammer": return "Jammer"
        case "taunt": return "Taunt"
        default:
            return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var primaryTint: Color {
        switch situation {
        case .outOfBounds: HuntColor.warning
        case .signalLost, .reconnecting: HuntColor.muted
        default: HuntColor.paper
        }
    }
}

struct EffectHudLine: Identifiable, Equatable {
    var id: String
    var text: String
}

private struct HuntProgressBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = LiveHUDLayout.barHeight

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HuntColor.line.opacity(0.8))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * progress)))
            }
        }
        .frame(height: height)
    }
}
