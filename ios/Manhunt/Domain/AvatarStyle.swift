import Foundation

/// Avatar color and ring assignment. Two players with the same initials must not look alike.
///
/// Rule (identical on web, see web/src/game/avatarStyle.ts):
///  1. Sort the roster by lowercase player id. That order is stable for the whole game.
///  2. Each player prefers palette slot `djb2(id) % palette.count`.
///  3. If a player with the same initials already holds that slot, take the next free slot.
///  4. The nth player with the same initials gets ring cue `n % 4`, so color-blind players
///     still have a shape difference. Players with unique initials get no ring.
///
/// TODO: profile photos. Needs upload, storage, moderation, and PII decisions first.
/// Do not add uploads here until those are made.
enum AvatarStyle {
    struct Style: Equatable {
        var colorIndex: Int
        /// 0 = no ring, 1 = solid, 2 = dashed, 3 = dotted.
        var cue: Int
    }

    /// RGB bytes. Order and values must match AVATAR_PALETTE on web. Every fill carries dark
    /// `HuntColor.ink` text at WCAG AA contrast (asserted in AvatarStyleTests).
    static let paletteRGB: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (0xF2, 0xDB, 0x47), (0xF2, 0x9E, 0x29), (0x4F, 0xC3, 0xD9), (0xA0, 0x7B, 0xEF),
        (0xEE, 0x82, 0xBC), (0x5C, 0x8F, 0xF2), (0xB8, 0xD9, 0x5A), (0xD6, 0xA6, 0x7E),
        (0xA9, 0xB6, 0xFF), (0xF2, 0xB8, 0xA0), (0x7F, 0xE0, 0xC8), (0xD5, 0x8A, 0xF0),
    ]

    static let ringCueCount = 4

    /// First letter of the first two words, uppercased. "?" for an empty name.
    static func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    /// djb2 over UTF-8 bytes in 32-bit arithmetic, same as the web helper.
    static func idHash(_ id: String) -> UInt32 {
        var hash: UInt32 = 5381
        for byte in id.utf8 {
            hash = hash &* 33 &+ UInt32(byte)
        }
        return hash
    }

    /// Keyed by the id exactly as passed in.
    static func assign(
        players: [(id: String, name: String)],
        paletteCount: Int = AvatarStyle.paletteRGB.count
    ) -> [String: Style] {
        let sorted = players.sorted { $0.id.lowercased() < $1.id.lowercased() }
        var takenByInitials: [String: Set<Int>] = [:]
        var countByInitials: [String: Int] = [:]
        var result: [String: Style] = [:]
        for player in sorted {
            let groupKey = initials(from: player.name)
            var taken = takenByInitials[groupKey] ?? []
            // Count players, not distinct colors: once the palette is used up `taken` stops growing.
            let seen = countByInitials[groupKey] ?? 0
            let preferred = Int(idHash(player.id.lowercased()) % UInt32(paletteCount))
            // If every slot is taken the duplicate is unavoidable, so keep the preferred slot
            // and let the ring cue tell them apart.
            var colorIndex = preferred
            for step in 0..<paletteCount {
                let candidate = (preferred + step) % paletteCount
                if !taken.contains(candidate) {
                    colorIndex = candidate
                    break
                }
            }
            result[player.id] = Style(colorIndex: colorIndex, cue: seen % ringCueCount)
            taken.insert(colorIndex)
            countByInitials[groupKey] = seen + 1
            takenByInitials[groupKey] = taken
        }
        return result
    }

    private static func channel(_ value: UInt8) -> Double {
        let v = Double(value) / 255
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ rgb: (r: UInt8, g: UInt8, b: UInt8)) -> Double {
        0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
    }

    /// WCAG 2.x contrast ratio between two colors.
    static func contrastRatio(
        _ a: (r: UInt8, g: UInt8, b: UInt8),
        _ b: (r: UInt8, g: UInt8, b: UInt8)
    ) -> Double {
        let high = max(luminance(a), luminance(b))
        let low = min(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
    }

    /// Same value as AVATAR_TEXT on web and `HuntColor.ink`.
    static let textRGB: (r: UInt8, g: UInt8, b: UInt8) = (0x11, 0x16, 0x13)
}
