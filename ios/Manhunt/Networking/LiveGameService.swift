import Foundation

/// REST + WebSocket implementation used by sideloaded phones against the home server.
final class LiveGameService: GameService {
    private let client: APIClient
    private let socket = GameSocket()
    private(set) var joinCalls = 0
    var onView: ((PlayerViewDTO) -> Void)?
    var onQR: ((String) -> Void)?
    var onEvent: ((BannerDTO) -> Void)?
    var onReconnect: ((Bool) -> Void)?

    init(baseURL: URL) {
        client = APIClient(baseURL: baseURL)
        socket.onView = { [weak self] view in self?.onView?(view) }
        socket.onQR = { [weak self] token in self?.onQR?(token) }
        socket.onEvent = { [weak self] banner in self?.onEvent?(banner) }
        socket.onReconnect = { [weak self] reconnecting in self?.onReconnect?(reconnecting) }
    }

    var token: String? {
        get { client.token }
        set { client.token = newValue }
    }

    func updateBaseURL(_ url: URL) {
        client.baseURL = url
    }

    func signIn(displayName: String) async throws -> AuthOut {
        let auth: AuthOut = try await client.post("/v1/auth/dev", body: DevAuthBody(displayName: displayName))
        client.token = auth.accessToken
        return auth
    }

    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthOut {
        let auth: AuthOut = try await client.post(
            "/v1/auth/apple",
            body: AppleAuthBody(identityToken: identityToken, displayName: displayName)
        )
        client.token = auth.accessToken
        return auth
    }

    func registerDeviceToken(_ token: String) async throws {
        struct Body: Encodable { var token: String }
        let _: EmptyBody = try await client.put("/v1/me/device-token", body: Body(token: token))
    }

    func arenas() async throws -> [Arena] {
        try await client.get("/v1/arenas")
    }

    func createArena(_ arena: Arena) async throws -> Arena {
        try await client.post("/v1/arenas", body: arena)
    }

    func createGame(
        arenaID: UUID,
        presetID: String,
        overrides: [String: [String: RuleValue]]
    ) async throws -> PlayerViewDTO {
        let created: GameCreatedDTO = try await client.post(
            "/v1/games",
            body: CreateGameBody(arenaId: arenaID, presetId: presetID, overrides: overrides)
        )
        return try await view(gameID: created.id)
    }

    func timeline(gameID: UUID) async throws -> [TimelineEventDTO] {
        let body: TimelineOut = try await client.get("/v1/games/\(gameID.uuidString)/events")
        return body.events
    }

    func join(code: String) async throws -> PlayerViewDTO {
        joinCalls += 1
        let created: GameCreatedDTO = try await client.post("/v1/games/join", body: JoinBody(joinCode: code))
        return try await view(gameID: created.id)
    }

    func randomizeRoles(gameID: UUID, hiderCount: Int) async throws -> PlayerViewDTO {
        try await client.post("/v1/games/\(gameID.uuidString)/roles", body: RoleRandomBody(hiderCount: hiderCount))
    }

    func setRole(gameID: UUID, playerID: UUID, role: PlayerRole) async throws -> PlayerViewDTO {
        try await client.post(
            "/v1/games/\(gameID.uuidString)/roles",
            body: RoleManualBody(assignments: [playerID.uuidString: role.rawValue])
        )
    }

    func start(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/start")
    }

    func pause(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/pause")
    }

    func resume(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/resume")
    }

    func end(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/end")
    }

    func view(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.get("/v1/games/\(gameID.uuidString)")
    }

    func claimQR(gameID: UUID, token: String) async throws {
        let _: [String: String] = try await client.post(
            "/v1/games/\(gameID.uuidString)/tags/qr",
            body: QRBody(token: token)
        )
    }

    func connect(gameID: UUID) {
        guard let token = client.token else { return }
        var components = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false)
        let wsScheme = client.baseURL.scheme == "https" ? "wss" : "ws"
        components?.scheme = wsScheme
        components?.path = "/v1/games/\(gameID.uuidString)/ws"
        guard let url = components?.url else { return }
        socket.connect(url: url, token: token)
    }

    func sendLocation(
        lat: Double,
        lon: Double,
        accuracyM: Double,
        flag: String = "normal",
        battery: Float? = nil
    ) {
        socket.sendLocation(lat: lat, lon: lon, accuracyM: accuracyM, flag: flag, battery: battery)
    }

    func disconnect() {
        socket.disconnect()
    }

    func purchase(gameID: UUID, powerID: String, extra: [String: Double]) async throws -> PlayerViewDTO {
        struct Body: Encodable {
            var id: String
            var lat: Double?
            var lon: Double?
        }
        return try await client.post(
            "/v1/games/\(gameID.uuidString)/power-ups",
            body: Body(id: powerID, lat: extra["lat"], lon: extra["lon"])
        )
    }
}
