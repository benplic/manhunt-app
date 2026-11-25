import SwiftUI

private struct AvatarStylesKey: EnvironmentKey {
    static let defaultValue: [String: AvatarStyle.Style] = [:]
}

extension EnvironmentValues {
    /// Roster-wide avatar colors and ring cues, set once at the root so a player looks the
    /// same on the map, in the lobby, and on the leaderboard.
    var avatarStyles: [String: AvatarStyle.Style] {
        get { self[AvatarStylesKey.self] }
        set { self[AvatarStylesKey.self] = newValue }
    }
}

/// Initials avatar until photo upload ships. Same-initial players get different colors and a
/// ring pattern (none, solid, dashed, dotted) so color is never the only cue.
/// TODO: profile photos. Needs upload, storage, moderation, and PII decisions first.
/// TODO: reuse this view in chat rows when messaging lands; filter blocked ids via PlayerBlockList.
struct PlayerAvatar: View {
    @Environment(\.avatarStyles) private var avatarStyles
    var name: String
    var playerID: String
    var size: CGFloat = 28
    /// Optional future photo URL; ignored until upload exists.
    var avatarURL: String? = nil

    var body: some View {
        let style = avatarStyles[playerID]
        ZStack {
            Circle()
                .fill(Self.fillColor(for: playerID, style: style))
            ring(cue: style?.cue ?? 0)
            Text(Self.initials(from: name))
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(HuntColor.ink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ring(cue: Int) -> some View {
        switch cue {
        case 1:
            Circle().strokeBorder(HuntColor.ink, lineWidth: 2)
        case 2:
            Circle().strokeBorder(HuntColor.ink, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        case 3:
            Circle().strokeBorder(HuntColor.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 4]))
        default:
            EmptyView()
        }
    }

    static func initials(from name: String) -> String {
        AvatarStyle.initials(from: name)
    }

    /// Roster style when known, else the id's preferred palette slot (before a roster exists).
    static func fillColor(for playerID: String, style: AvatarStyle.Style? = nil) -> Color {
        let slot = style?.colorIndex
            ?? Int(AvatarStyle.idHash(playerID.lowercased()) % UInt32(AvatarStyle.paletteRGB.count))
        let rgb = AvatarStyle.paletteRGB[slot]
        return Color(
            red: Double(rgb.r) / 255,
            green: Double(rgb.g) / 255,
            blue: Double(rgb.b) / 255
        )
    }
}
