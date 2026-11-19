import Foundation

/// Client-side display name guard. Tokens must match `server/app/auth/names.py`.
enum DisplayNameRules {
    private static let blocked: Set<String> = [
        "nigger",
        "faggot",
        "retard",
    ]

    static func isAllowed(_ name: String) -> Bool {
        let cleaned = normalize(name)
        guard !cleaned.isEmpty, cleaned.count <= 40 else { return false }
        return tokenize(cleaned).isDisjoint(with: blocked)
    }

    private static func normalize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func tokenize(_ cleaned: String) -> Set<String> {
        var tokens = Set<String>()
        var current = ""
        for character in cleaned {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.insert(current.lowercased())
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.insert(current.lowercased())
        }
        return tokens
    }
}