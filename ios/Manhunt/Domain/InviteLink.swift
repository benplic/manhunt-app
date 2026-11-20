import Foundation

/// Invite URLs open the public web client. A QR code carries the same URL.
/// `app.manhunt.ios` is still accepted so an older lobby QR joins inside the app.
enum InviteLink {
    /// Host that actually serves the browser client. Not the Sign in with Apple audience.
    static let webOrigin = "https://manhunt-app.pages.dev"

    static func url(joinCode: String) -> URL {
        let code = JoinCode.normalize(joinCode)
        return URL(string: "\(webOrigin)/join/\(code)")!
    }

    static func joinCode(from url: URL) -> String? {
        // manhunt://join/PARK42 puts the code in the path and "join" in the host.
        if url.scheme == "manhunt", url.host == "join" {
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return valid(raw)
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let raw = items.first(where: { $0.name == "join" })?.value,
           let code = valid(raw) {
            return code
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
