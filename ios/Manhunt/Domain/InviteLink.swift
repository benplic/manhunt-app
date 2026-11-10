import Foundation

/// Invite URLs are universal links. A QR code carries the same URL, and scanning
/// it joins the game the same way opening the link does.
enum InviteLink {
    static func url(joinCode: String) -> URL {
        let code = JoinCode.normalize(joinCode)
        return URL(string: "https://app.manhunt.ios/join/\(code)")!
    }

    static func joinCode(from url: URL) -> String? {
        // manhunt://join/PARK42 puts the code in the path and "join" in the host.
        if url.scheme == "manhunt", url.host == "join" {
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return valid(raw)
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let join = parts.firstIndex(of: "join"), parts.indices.contains(join + 1) else {
            return nil
        }
        return valid(parts[join + 1])
    }

    /// QR payloads are the invite URL. A bare join code still works.
    static func joinCode(fromQR payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = joinCode(from: url) {
            return code
        }
        return valid(trimmed)
    }

    private static func valid(_ raw: String) -> String? {
        let code = JoinCode.normalize(raw)
        return JoinCode.isValid(code) ? code : nil
    }
}
