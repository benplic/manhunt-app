import Foundation

/// Six-character codes. Ambiguous glyphs (0, O, 1, I, L) are rejected so people
/// can read a code off a screen in a park.
enum JoinCode {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isValid(_ raw: String) -> Bool {
        let code = normalize(raw)
        guard code.count == 6 else { return false }
        return code.allSatisfy { alphabet.contains($0) }
    }

    static func generate<R: RandomNumberGenerator>(using rng: inout R) -> String {
        String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }
}
