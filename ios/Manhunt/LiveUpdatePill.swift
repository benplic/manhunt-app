import SwiftUI
import UIKit

/// Flush rounded pill under the live HUD for incoming game events and notices.
struct LiveUpdatePill: View {
    var triggerKey: String
    var text: String
    var tone: String

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HuntColor.paper)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.65), lineWidth: 1.5)
        )
        .scaleEffect(pulse ? 1.02 : 1.0)
        .onAppear { triggerFeedback() }
        .onChange(of: triggerKey) { _, _ in triggerFeedback() }
    }

    private func triggerFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.16)) { pulse = true }
        withAnimation(.easeOut(duration: 0.25).delay(0.16)) { pulse = false }
    }

    private var accent: Color {
        switch tone {
        case "warning": HuntColor.warning
        case "safety", "danger": HuntColor.danger
        case "success": HuntColor.signal
        default: HuntColor.paper
        }
    }
}
