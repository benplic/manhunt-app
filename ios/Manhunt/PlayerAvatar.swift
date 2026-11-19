import SwiftUI

/// Initials avatar until photo upload ships. Color is stable per player id.
/// TODO: reuse this view in chat rows when messaging lands; filter blocked ids via PlayerBlockList.
struct PlayerAvatar: View {
    var name: String
    var playerID: String
    var size: CGFloat = 28
    /// Optional future photo URL; ignored until upload exists.
    var avatarURL: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(Self.fillColor(for: playerID))
            Text(Self.initials(from: name))
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(HuntColor.paper)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    static func fillColor(for playerID: String) -> Color {
        var hash: UInt64 = 5381
        for byte in playerID.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let palette: [Color] = [
            HuntColor.seeker,
            HuntColor.hider,
            HuntColor.signal,
            HuntColor.warning,
            Color(red: 0.35, green: 0.72, blue: 0.78),
            Color(red: 0.62, green: 0.48, blue: 0.92),
            Color(red: 0.92, green: 0.55, blue: 0.35),
            Color(red: 0.45, green: 0.78, blue: 0.52),
        ]
        return palette[Int(hash % UInt64(palette.count))]
    }
}
