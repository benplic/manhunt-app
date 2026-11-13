import SwiftUI

struct PingFlashOverlay: View {
    var pulse: PingPulse?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Frame {
        var glow = 0.0
        var ring = 0.2
        var ringOpacity = 0.0
        var label = 0.0
    }

    var body: some View {
        let isHider = pulse?.role == .hider
        let tint = isHider ? HuntColor.danger : HuntColor.signal
        KeyframeAnimator(initialValue: Frame(), trigger: pulse?.id) { frame in
            ZStack {
                Rectangle()
                    .strokeBorder(tint, lineWidth: 30)
                    .blur(radius: 16)
                    .opacity(frame.glow)
                if !reduceMotion {
                    Circle()
                        .stroke(tint, lineWidth: 6)
                        .scaleEffect(frame.ring)
                        .opacity(frame.ringOpacity)
                }
                Text(isHider ? "PINGED" : "PING")
                    .font(HuntFont.title(40))
                    .tracking(4)
                    .foregroundStyle(HuntColor.paper)
                    .shadow(color: .black.opacity(0.7), radius: 8)
                    .opacity(frame.label)
            }
            .ignoresSafeArea()
        } keyframes: { _ in
            KeyframeTrack(\.glow) {
                LinearKeyframe(0.95, duration: 0.12)
                CubicKeyframe(0, duration: 0.85)
            }
            KeyframeTrack(\.ring) { CubicKeyframe(2.6, duration: 1.0) }
            KeyframeTrack(\.ringOpacity) {
                LinearKeyframe(0.85, duration: 0.1)
                CubicKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.label) {
                LinearKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 0.45)
                CubicKeyframe(0, duration: 0.4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(trigger: pulse?.id) { _, new in
            guard new != nil else { return nil }
            return isHider ? .warning : .impact(weight: .medium)
        }
    }
}
