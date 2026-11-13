import SwiftUI

/// How a tap should feel. Light for chrome, medium for the action the screen is about.
enum HuntHaptic {
    case light, medium, selection, warning

    var feedback: SensoryFeedback {
        switch self {
        case .light: .impact(flexibility: .soft, intensity: 0.6)
        case .medium: .impact(weight: .medium)
        case .selection: .selection
        case .warning: .warning
        }
    }
}

/// Shared press feel: spring scale, slight dim, haptic on touch-down. A disabled button stays
/// silent. Reduce Motion keeps the dim and drops the scale.
struct HuntPressStyle: ButtonStyle {
    var haptic: HuntHaptic

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, haptic: haptic)
    }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        let haptic: HuntHaptic
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
                .sensoryFeedback(haptic.feedback, trigger: configuration.isPressed) { _, pressed in
                    pressed && isEnabled
                }
        }
    }
}

extension ButtonStyle where Self == HuntPressStyle {
    static var huntPress: HuntPressStyle { HuntPressStyle(haptic: .light) }
    static func huntPress(_ haptic: HuntHaptic) -> HuntPressStyle { HuntPressStyle(haptic: haptic) }
}
