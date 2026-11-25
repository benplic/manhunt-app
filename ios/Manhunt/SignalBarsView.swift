import SwiftUI

/// Four bars for this phone's own socket, next to the host controls in the top bar.
/// Solid bars are on, outlined bars are off, and the two worst states add a "!", so the
/// meaning never depends on color alone. Tap explains it through the alert queue.
struct SignalBarsView: View {
    /// Reads the socket on every refresh. Nil hides the meter (previews, fake service).
    let health: () -> SocketHealth?
    let onTap: () -> Void

    private static let barCount = 4

    var body: some View {
        // The 5 s window needs about 1 s resolution, so re-read once a second.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let snapshot = health() {
                let reading = SocketMeter.reading(for: snapshot, now: timeline.date)
                Button(action: onTap) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<Self.barCount, id: \.self) { index in
                            bar(index: index, on: index < reading.bars, color: tint(reading.label))
                        }
                        if reading.bars <= 1 {
                            Text("!")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(tint(reading.label))
                                .padding(.leading, 2)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.black.opacity(0.55), in: Capsule())
                }
                .buttonStyle(.huntPress(.light))
                .accessibilityLabel(reading.accessibilityLabel)
                .accessibilityHint("Shows how recently the hunt server was heard from.")
                .accessibilityIdentifier("signal-bars")
            }
        }
    }

    private func bar(index: Int, on: Bool, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(on ? color : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(color, lineWidth: 1))
            .frame(width: 4, height: CGFloat(6 + index * 4))
            .accessibilityHidden(true)
    }

    private func tint(_ label: SocketMeter.Label) -> Color {
        switch label {
        case .good: HuntColor.hider
        case .slow: HuntColor.signal
        case .reconnecting, .unstable: HuntColor.warning
        case .down: HuntColor.danger
        }
    }
}
