import Foundation

/// REST + WebSocket implementation used by sideloaded phones against the home server.
final class LiveGameService: GameService {
    private let client: APIClient
    private let socket = GameSocket()
    private(set) var joinCalls = 0
    /// Rotating refresh token from the last auth response. Cleared on sign-out.
    var refreshToken: String?
    /// Called when a refresh attempt fails so the store can sign out.
    var onRefreshFailed: (() -> Void)?
    /// Called after a successful refresh so the store can persist both tokens.
    var onTokensRotated: ((AuthOut) -> Void)?
    var onView: ((PlayerViewDTO) -> Void)?
    var onQR: ((String) -> Void)?
    var onEvent: ((BannerDTO) -> Void)?
    var onReconnect: ((Bool) -> Void)?
    var onUWBPeers: (([UWBPeer]) -> Void)?
    var onSendFailure: ((String) -> Void)? {
        get { socket.onSendFailure }
        set { socket.onSendFailure = newValue }
    }

    init(baseURL: URL) {
        client = APIClient(baseURL: baseURL)
        socket.onView = { [weak self] view in self?.onView?(view) }
        socket.onQR = { [weak self] token in self?.onQR?(token) }
        socket.onEvent = { [weak self] banner in self?.onEvent?(banner) }
        socket.onReconnect = { [weak self] reconnecting in self?.onReconnect?(reconnecting) }
        socket.onUWBPeers = { [weak self] peers in self?.onUWBPeers?(peers) }
        client.refreshAccessToken = { [weak self] in
            try await self?.rotateAccessToken()
        }
    }

    var token: String? {
        get { client.token }
        set { client.token = newValue }
    }

    private func rotateAccessToken() async throws {
        guard let refreshToken else {
            onRefreshFailed?()
            throw ServiceError(code: .unauthorized, message: "Session expired.")
        }
        do {
            let auth = try await refresh(refreshToken: refreshToken)
            self.refreshToken = auth.refreshToken ?? refreshToken
            onTokensRotated?(auth)
        } catch {
            onRefreshFailed?()
            throw error
        }
    }

    func updateBaseURL(_ url: URL) {
        client.baseURL = url
    }

    func signIn(displayName: String) async throws -> AuthOut {
        let auth: AuthOut = try await client.post("/v1/auth/dev", body: DevAuthBody(displayName: displayName))
        client.token = auth.accessToken
        refreshToken = auth.refreshToken
        return auth
    }

    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthOut {
        let auth: AuthOut = try await client.post(
            "/v1/auth/apple",
            body: AppleAuthBody(identityToken: identityToken, displayName: displayName)
        )
        client.token = auth.accessToken
        refreshToken = auth.refreshToken
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

    func updateArena(_ arena: Arena) async throws -> Arena {
        try await client.put("/v1/arenas/\(arena.id.uuidString)", body: arena)
    }

    func deleteArena(id: UUID) async throws {
        try await client.delete("/v1/arenas/\(id.uuidString)")
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

    func randomizeRoles(gameID: UUID, seekerCount: Int) async throws -> PlayerViewDTO {
        try await client.post("/v1/games/\(gameID.uuidString)/roles", body: RoleRandomBody(seekerCount: seekerCount))
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

    func leave(gameID: UUID) async throws {
        let _: EmptyBody = try await client.postEmpty("/v1/games/\(gameID.uuidString)/leave")
    }

    func removePlayer(gameID: UUID, playerID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty(
            "/v1/games/\(gameID.uuidString)/players/\(playerID.uuidString)/remove"
        )
    }

    func undoTag(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/tags/undo")
    }

    func ackSafety(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/safety/ack")
    }

    func taunt(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.postEmpty("/v1/games/\(gameID.uuidString)/taunt")
    }

    func view(gameID: UUID) async throws -> PlayerViewDTO {
        try await client.get("/v1/games/\(gameID.uuidString)")
    }

    func refresh(refreshToken: String) async throws -> AuthOut {
        struct Body: Encodable {
            var refreshToken: String
            enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
        }
        let auth: AuthOut = try await client.post(
            "/v1/auth/refresh",
            body: Body(refreshToken: refreshToken)
        )
        client.token = auth.accessToken
        return auth
    }

    func claimQR(gameID: UUID, token: String) async throws {
        let _: [String: String] = try await client.post(
            "/v1/games/\(gameID.uuidString)/tags/qr",
            body: QRBody(token: token)
        )
    }

    func claimUWB(gameID: UUID, hiderID: UUID) async throws {
        let _: [String: String] = try await client.post(
            "/v1/games/\(gameID.uuidString)/tags/uwb",
            body: UwbTagBody(hiderId: hiderID)
        )
    }

    func sendUWBToken(_ token: String) {
        socket.sendUWBToken(token)
    }

    func sendUWBRange(peerID: UUID, distanceM: Double) {
        socket.sendUWBRange(peerID: peerID, distanceM: distanceM)
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

    func fetchModules() async throws -> [VisualModule] {
        let response: ModulesResponse = try await client.get("/v1/modules")
        return ModuleForm.modules(from: response)
    }

    func savePreset(name: String, modules: [String: [String: RuleValue]]) async throws -> SavedPresetDTO {
        try await client.post("/v1/presets/saved", body: SavePresetBody(name: name, modules: modules))
    }

    func updatePreset(
        id: String,
        name: String,
        modules: [String: [String: RuleValue]]
    ) async throws -> SavedPresetDTO {
        try await client.put("/v1/presets/saved/\(id)", body: SavePresetBody(name: name, modules: modules))
    }

    func deletePreset(id: String) async throws {
        try await client.delete("/v1/presets/saved/\(id)")
    }

    func savedPresets() async throws -> [SavedPresetDTO] {
        try await client.get("/v1/presets/saved")
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

    func demo(gameID: UUID, action: String, params: [String: RuleValue]) async throws -> PlayerViewDTO {
        var payload = params
        payload["action"] = .string(action)
        return try await client.post("/v1/games/\(gameID.uuidString)/demo", body: payload)
    }
}
