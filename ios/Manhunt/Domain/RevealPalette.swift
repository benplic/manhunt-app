import SwiftUI

enum RevealPalette {
    /// Last byte of the UUID string. Stable across launches. Not sent by the server.
    static func index(for playerID: UUID) -> Int {
        let hex = playerID.uuidString.replacingOccurrences(of: "-", with: "")
        let byte = Int(hex.suffix(2), radix: 16) ?? 0
        return byte % 6
    }

    /// Violet, pink, cyan, lime, magenta, periwinkle.
    static func color(at index: Int) -> Color {
        HuntColor.revealPalette[abs(index) % HuntColor.revealPalette.count]
    }
}
