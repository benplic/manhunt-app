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
            content(PhaseClock(snapshot: snapshot, paused: paused, leadS: lead))
        }
    }

    private func content(_ clock: PhaseClock) -> some View {
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

    private var primaryTint: Color {
        switch situation {
        case .outOfBounds: HuntColor.warning
        case .signalLost, .reconnecting: HuntColor.muted
        default: HuntColor.paper
        }
    }
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
