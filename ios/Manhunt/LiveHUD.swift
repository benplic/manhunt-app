import SwiftUI

struct LiveHUD: View {
    var clock: PhaseClock
    var situation: LiveSituation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(clock.primaryLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HuntColor.muted)
                Text(clock.primaryClock)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HuntProgressBar(
                    progress: clock.primaryProgress,
                    tint: situation == .headStart ? HuntColor.signal : HuntColor.paper
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(HuntColor.line)
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Next ping")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HuntColor.muted)
                    Spacer(minLength: 4)
                    Text(clock.pingClock ?? "Off")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(HuntColor.paper)
                }
                HuntProgressBar(
                    progress: clock.pingProgress,
                    tint: clock.pingClock != nil ? HuntColor.seeker : HuntColor.line
                )
                if let zoneLine = clock.zoneLine {
                    Text(zoneLine)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(clock.zoneImminent ? HuntColor.warning : HuntColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        .frame(height: 5)
    }
}
