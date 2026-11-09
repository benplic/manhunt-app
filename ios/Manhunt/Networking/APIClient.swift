import Foundation

/// Thin REST client. First request of a session waits up to 60 s so a sleeping
/// Azure replica (Phase 2) or a slow home Docker boot can finish waking.
final class APIClient: @unchecked Sendable {
    var baseURL: URL
    var token: String?
    private let session: URLSession
    private var hasCompletedFirstRequest = false

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "GET", path: path, body: Optional<EmptyBody>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(method: "POST", path: path, body: body)
    }

    func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "POST", path: path, body: Optional<EmptyBody>.none)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(method: "PUT", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyBody = try await send(method: "DELETE", path: path, body: Optional<EmptyBody>.none)
    }

    private func send<T: Decodable, B: Encodable>(method: String, path: String, body: B?) async throws -> T {
        let deadline = hasCompletedFirstRequest
            ? Date().addingTimeInterval(15)
            : Date().addingTimeInterval(60)
        var lastError: Error = ServiceError(code: .internal, message: "No request was sent.")
        var delay: TimeInterval = 1
        while Date() < deadline {
            do {
                let value: T = try await once(method: method, path: path, body: body)
                hasCompletedFirstRequest = true
                return value
            } catch let error as ServiceError {
                lastError = error
                // Auth and rule errors will not recover by waiting.
                if ![ErrorCode.internal, .rateLimited].contains(error.code),
                   error.code != .unauthorized
                {
                    throw error
                }
                if error.code == .unauthorized { throw error }
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 2, 8)
        }
        if let service = lastError as? ServiceError { throw service }
        throw ServiceError(
            code: .internal,
            message: "Is the home server running? Could not reach \(baseURL.absoluteString)."
        )
    }

    private func once<T: Decodable, B: Encodable>(method: String, path: String, body: B?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ServiceError(code: .internal, message: "Bad path \(path).")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError(code: .internal, message: "Is the home server running?")
        }
        if (200..<300).contains(http.statusCode) {
            if T.self == EmptyBody.self {
                return EmptyBody() as! T
            }
            if data.isEmpty, T.self == EmptyBody.self {
                return EmptyBody() as! T
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ServiceError(code: .internal, message: "The server sent a body this build cannot read.")
            }
        }
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            throw ServiceError(code: body.error.code, message: body.error.message)
        }
        throw ServiceError(code: .internal, message: "HTTP \(http.statusCode)")
    }
}

struct EmptyBody: Codable {}

struct CreateGameBody: Encodable {
    var arenaId: UUID
    var presetId: String
    var overrides: [String: [String: RuleValue]]

    enum CodingKeys: String, CodingKey {
        case arenaId = "arena_id"
        case presetId = "preset_id"
        case overrides
    }
}

struct JoinBody: Encodable {
    var joinCode: String
    enum CodingKeys: String, CodingKey { case joinCode = "join_code" }
}

struct RoleRandomBody: Encodable {
    var mode = "random"
    var hiderCount: Int
    enum CodingKeys: String, CodingKey {
        case mode
        case hiderCount = "hider_count"
    }
}

struct RoleManualBody: Encodable {
    var mode = "manual"
    var assignments: [String: String]
}

struct QRBody: Encodable {
    var token: String
}

struct DevAuthBody: Encodable {
    var displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

struct GameCreatedDTO: Codable {
    var id: UUID
    var joinCode: String
    var status: String
    enum CodingKeys: String, CodingKey {
        case id
        case joinCode = "join_code"
        case status
    }
}
