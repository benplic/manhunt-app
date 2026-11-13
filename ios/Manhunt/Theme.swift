import SwiftUI

/// Field-manual palette. Dark ground, one signal color, role colors that stay
/// distinct on a map.
enum HuntColor {
    static let ink = Color(red: 0.067, green: 0.086, blue: 0.075)
    static let inkRaised = Color(red: 0.12, green: 0.145, blue: 0.13)
    static let line = Color(red: 0.22, green: 0.26, blue: 0.23)
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.88)
    static let muted = Color(red: 0.67, green: 0.71, blue: 0.66)
    static let signal = Color(red: 0.93, green: 0.86, blue: 0.28)
    static let hider = Color(red: 0.22, green: 0.74, blue: 0.52)
    static let seeker = Color(red: 0.90, green: 0.33, blue: 0.25)
    static let safe = Color(red: 0.36, green: 0.56, blue: 0.95)
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.16)
    static let danger = Color(red: 0.86, green: 0.22, blue: 0.18)

    /// Violet, pink, cyan, lime, magenta, periwinkle — distinct from `safe`.
    static let revealPalette: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.96, green: 0.45, blue: 0.70),
        Color(red: 0.20, green: 0.85, blue: 0.85),
        Color(red: 0.78, green: 0.95, blue: 0.35),
        Color(red: 0.85, green: 0.25, blue: 0.55),
        Color(red: 0.75, green: 0.78, blue: 0.95),
    ]
}

enum HuntFont {
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}
