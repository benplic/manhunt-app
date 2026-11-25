import SwiftUI

/// Four bars for how recently a player's location was heard. This is freshness of the last
/// fix, never radio signal strength, and the accessibility label says so with "fix".
/// Solid bars are on, outlined bars are off, so the meaning never depends on color alone.
struct FixBarsView: View {
    let reading: FixFreshness.Reading

    private static let barCount = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < reading.bars ? tint : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 1).stroke(tint, lineWidth: 1))
                    .frame(width: 3, height: CGFloat(5 + index * 3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.label)
        .accessibilityIdentifier("fix-bars")
    }

    private var tint: Color {
        switch reading.bars {
        case 3...: HuntColor.hider
        case 2: HuntColor.signal
        default: HuntColor.danger
        }
    }
}
