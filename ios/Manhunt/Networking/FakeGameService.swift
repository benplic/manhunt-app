import Foundation

/// In-memory server for UI tests and screenshots. Join code PARK42 is the sample lobby.
final class FakeGameService: GameService {
    private(set) var joinCalls = 0
    private(set) var leaveCalls = 0
    private(set) var lastLocationFlag: String?
    private(set) var lastDeviceToken: String?
    private(set) var appleSignIns = 0
    private(set) var refreshCalls = 0
    private var signedIn: UserDTO?
    private(set) var storedArenas: [Arena]
    private var games: [UUID: FakeGame] = [:]
    private var presetsSaved: [SavedPresetDTO] = []
    private var issuedRefresh = "fake-refresh"
    /// The known park lobby, created on init so join("park42") works before create.
    private let park = UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!

    init(arenas: [Arena] = FakeGameService.seedArenas()) {
        storedArenas = arenas
        games[park] = FakeGame(
            id: park,
            joinCode: "PARK42",
            youAreHost: false,
            players: [
                FakePlayer(id: UUID(), name: "Jordan Blake", role: .seeker, isHost: true),
                FakePlayer(id: UUID(), name: "Casey Lee", role: .hider, isHost: false),
            ]
        )
    }

    static func seedArenas() -> [Arena] {
        [Arena.sampleSquare(), Arena.riversideSample(), Arena.schoolyardSample()]
    }

    func signIn(displayName: String) async throws -> AuthOut {
        signInSync(displayName)
    }

    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthOut {
        appleSignIns += 1
        _ = identityToken
        return signInSync(displayName ?? "Casey Lee")
    }

    func registerDeviceToken(_ token: String) async throws {
        lastDeviceToken = token
    }

    func recordLocationFlag(_ flag: String) {
        lastLocationFlag = flag
    }

    @discardableResult
    func signInSync(_ displayName: String) -> AuthOut {
        let user = UserDTO(id: signedIn?.id ?? UUID(), displayName: displayName)
        signedIn = user
        issuedRefresh = "fake-refresh-\(user.id.uuidString.prefix(8))"
        return AuthOut(
            accessToken: "fake",
            expiresAt: "2099-01-01T00:00:00Z",
            user: user,
            refreshToken: issuedRefresh
        )
    }

    func refresh(refreshToken: String) async throws -> AuthOut {
        refreshCalls += 1
        guard refreshToken == issuedRefresh, let user = signedIn else {
            throw ServiceError(code: .unauthorized, message: "Refresh rejected.")
        }
        issuedRefresh = "fake-refresh-rotated-\(refreshCalls)"
        return AuthOut(
            accessToken: "fake-rotated-\(refreshCalls)",
            expiresAt: "2099-01-01T00:00:00Z",
            user: user,
            refreshToken: issuedRefresh
        )
    }

    func arenas() async throws -> [Arena] { storedArenas }

    /// Next createArena throws this and then clears it. Tests use it for a visible save failure.
    var nextArenaError: ServiceError?

    func createArena(_ arena: Arena) async throws -> Arena {
        if let nextArenaError {
            self.nextArenaError = nil
            throw nextArenaError
        }
        storedArenas.append(arena)
        return arena
    }

    func updateArena(_ arena: Arena) async throws -> Arena {
        guard let index = storedArenas.firstIndex(where: { $0.id == arena.id }) else {
            throw ServiceError(code: .arenaNotFound, message: "Arena not found.")
        }
        storedArenas[index] = arena
        return arena
    }

    func deleteArena(id: UUID) async throws {
        guard storedArenas.contains(where: { $0.id == id }) else {
            throw ServiceError(code: .arenaNotFound, message: "Arena not found.")
        }
        storedArenas.removeAll { $0.id == id }
    }

    func createGame(
        arenaID: UUID,
        presetID: String,
        overrides: [String: [String: RuleValue]]
    ) async throws -> PlayerViewDTO {
        _ = overrides
        return try createGameSync(arenaID: arenaID, presetID: presetID)
    }

    func createGameSync(arenaID: UUID, presetID: String) throws -> PlayerViewDTO {
        guard storedArenas.contains(where: { $0.id == arenaID }) else {
            throw ServiceError(code: .arenaNotFound, message: "Arena not found.")
        }
        let id = UUID()
        let you = signedIn?.displayName ?? "You"
        let game = FakeGame(
            id: id,
            joinCode: JoinCode.generate(using: &rng),
            youAreHost: true,
            players: [
                FakePlayer(id: signedIn?.id ?? UUID(), name: you, role: .unassigned, isHost: true),
                FakePlayer(id: UUID(), name: "Riley Chen", role: .unassigned, isHost: false),
            ]
        )
        games[id] = game
        return game.view()
    }

    func join(code: String) async throws -> PlayerViewDTO {
        try joinSync(code: code)
    }

    func joinSync(code: String) throws -> PlayerViewDTO {
        joinCalls += 1
        let normalized = JoinCode.normalize(code)
        guard let game = games.values.first(where: { $0.joinCode == normalized }) else {
            throw ServiceError(code: .gameNotFound, message: "No game is using that code.")
        }
        return game.view()
    }

    func randomizeRoles(gameID: UUID, hiderCount: Int) async throws -> PlayerViewDTO {
        try randomizeRolesSync(gameID: gameID, hiderCount: hiderCount)
    }

    func randomizeRolesSync(gameID: UUID, hiderCount: Int) throws -> PlayerViewDTO {
        guard var game = games[gameID] else { throw ServiceError(code: .gameNotFound, message: "") }
        let assigned = RoleAssigner.assign(
            playerIDs: game.players.map(\.id),
            hiderCount: hiderCount,
            using: &rng
        )
        for index in game.players.indices {
            game.players[index].role = assigned[game.players[index].id] ?? .unassigned
        }
        games[gameID] = game
        return game.view()
    }

    func setRole(gameID: UUID, playerID: UUID, role: PlayerRole) async throws -> PlayerViewDTO {
        try setRoleSync(gameID: gameID, playerID: playerID, role: role)
    }

    func setRoleSync(gameID: UUID, playerID: UUID, role: PlayerRole) throws -> PlayerViewDTO {
        guard var game = games[gameID] else { throw ServiceError(code: .gameNotFound, message: "") }
        guard let index = game.players.firstIndex(where: { $0.id == playerID }) else {
            throw ServiceError(code: .notAMember, message: "")
        }
        game.players[index].role = role
        games[gameID] = game
        return game.view()
    }

    func start(gameID: UUID) async throws -> PlayerViewDTO {
        try startSync(gameID: gameID)
    }

    func startSync(gameID: UUID) throws -> PlayerViewDTO {
        guard var game = games[gameID] else { throw ServiceError(code: .gameNotFound, message: "") }
        let roles = Set(game.players.map(\.role))
        guard roles.contains(.hider), roles.contains(.seeker) else {
            throw ServiceError(code: .needBothRoles, message: "Need both roles.")
        }
        game.phase = .headStart
        games[gameID] = game
        return game.view()
    }

    func pause(gameID: UUID) async throws -> PlayerViewDTO {
        try mutate(gameID) { $0.phase = .paused }
    }

    func resume(gameID: UUID) async throws -> PlayerViewDTO {
        try mutate(gameID) { $0.phase = .active }
    }

    func end(gameID: UUID) async throws -> PlayerViewDTO {
        try endSync(gameID: gameID)
    }

    func endSync(gameID: UUID) throws -> PlayerViewDTO {
        try mutate(gameID) { $0.phase = .ended }
    }

    /// Test helper: jump past head start so power-ups / taunt can fire.
    func advanceToActive(gameID: UUID) throws -> PlayerViewDTO {
        try mutate(gameID) { $0.phase = .active }
    }

    func setTagMethod(gameID: UUID, method: String) throws -> PlayerViewDTO {
        try mutate(gameID) { $0.tagMethod = method }
    }

    func leave(gameID: UUID) async throws {
        leaveCalls += 1
        guard var game = games[gameID], let you = signedIn else {
            throw ServiceError(code: .gameNotFound, message: "")
        }
        game.players.removeAll { $0.id == you.id }
        games[gameID] = game
    }

    func removePlayer(gameID: UUID, playerID: UUID) async throws -> PlayerViewDTO {
        try mutate(gameID) { game in
            game.players.removeAll { $0.id == playerID }
        }
    }

    func undoTag(gameID: UUID) async throws -> PlayerViewDTO {
        try mutate(gameID) { game in
            for index in game.players.indices where game.players[index].role == .hider {
                game.players[index].status = .active
            }
            game.undidTag = true
        }
    }

    func ackSafety(gameID: UUID) async throws -> PlayerViewDTO {
        try mutate(gameID) { $0.ackedSafety = true }
    }

    func taunt(gameID: UUID) async throws -> PlayerViewDTO {
        guard var game = games[gameID], let you = signedIn else {
            throw ServiceError(code: .gameNotFound, message: "")
        }
        guard let index = game.players.firstIndex(where: { $0.id == you.id }) else {
            throw ServiceError(code: .notAMember, message: "")
        }
        guard game.players[index].role == .hider, game.phase == .active else {
            throw ServiceError(code: .wrongPhase, message: "Taunt only during the hunt.")
        }
        game.players[index].points += 12
        game.taunted = true
        games[gameID] = game
        return game.view()
    }

    func view(gameID: UUID) async throws -> PlayerViewDTO {
        guard let game = games[gameID] else { throw ServiceError(code: .gameNotFound, message: "") }
        return game.view()
    }

    func timeline(gameID: UUID) async throws -> [TimelineEventDTO] {
        guard games[gameID] != nil else { throw ServiceError(code: .gameNotFound, message: "") }
        return [
            TimelineEventDTO(seq: 1, type: "started", payload: TimelinePayloadDTO(text: "The hunt is on.", tone: "info")),
            TimelineEventDTO(seq: 2, type: "ended", payload: TimelinePayloadDTO(text: "Host ended.", tone: "info")),
        ]
    }

    func claimQR(gameID: UUID, token: String) async throws {
        guard games[gameID] != nil else { throw ServiceError(code: .gameNotFound, message: "") }
        if token.isEmpty { throw ServiceError(code: .tokenInvalid, message: "Empty token.") }
    }

    func claimUWB(gameID: UUID, hiderID: UUID) async throws {
        guard games[gameID] != nil else { throw ServiceError(code: .gameNotFound, message: "") }
        _ = hiderID
    }

    /// Tests hold the preset screen closed until the schema fetch finishes.
    var moduleFetchDelay: Duration = .zero

    func fetchModules() async throws -> [VisualModule] {
        if moduleFetchDelay > .zero {
            try await Task.sleep(for: moduleFetchDelay)
        }
        return ModuleForm.offlineModules()
    }

    func savePreset(name: String, modules: [String: [String: RuleValue]]) async throws -> SavedPresetDTO {
        let preset = SavedPresetDTO(id: UUID().uuidString, name: name, modules: modules)
        presetsSaved.insert(preset, at: 0)
        return preset
    }

    func updatePreset(
        id: String,
        name: String,
        modules: [String: [String: RuleValue]]
    ) async throws -> SavedPresetDTO {
        guard let index = presetsSaved.firstIndex(where: { $0.id == id }) else {
            throw ServiceError(code: .internal, message: "Preset not found.")
        }
        let preset = SavedPresetDTO(id: id, name: name, modules: modules)
        presetsSaved[index] = preset
        return preset
    }

    func deletePreset(id: String) async throws {
        guard presetsSaved.contains(where: { $0.id == id }) else {
            throw ServiceError(code: .internal, message: "Preset not found.")
        }
        presetsSaved.removeAll { $0.id == id }
    }

    func savedPresets() async throws -> [SavedPresetDTO] {
        presetsSaved
    }

    func purchase(gameID: UUID, powerID: String, extra: [String: Double]) async throws -> PlayerViewDTO {
        guard let game = games[gameID] else { throw ServiceError(code: .gameNotFound, message: "") }
        // Mirror the server play-area gate so decoy UI tests can assert TARGET_OUTSIDE.
        if powerID == "decoy" {
            guard let lat = extra["lat"], let lon = extra["lon"] else {
                throw ServiceError(code: .needsTarget, message: "Decoy needs a point.")
            }
            let point = GeoPoint(latitude: lat, longitude: lon)
            if !ArenaGeometry.contains(point, in: Arena.sampleSquare().boundary) {
                throw ServiceError(code: .targetOutside, message: "Outside play area.")
            }
        }
        return game.view()
    }

    private func mutate(_ gameID: UUID, _ body: (inout FakeGame) -> Void) throws -> PlayerViewDTO {
        guard var game = games[gameID] else { throw ServiceError(code: .gameNotFound, message: "") }
        body(&game)
        games[gameID] = game
        return game.view()
    }

    private var rng = SplitMix64(state: 7)
}

private struct FakePlayer {
    var id: UUID
    var name: String
    var role: PlayerRole
    var isHost: Bool
    var status: PlayerStatus = .active
    var points: Int = 100
}

private struct FakeGame {
    var id: UUID
    var joinCode: String
    var youAreHost: Bool
    var players: [FakePlayer]
    var phase: MatchPhase = .lobby
    var undidTag = false
    var ackedSafety = false
    var taunted = false
    var tagMethod: String = "qr"

    func view() -> PlayerViewDTO {
        let you = players.first(where: { $0.isHost == youAreHost }) ?? players[0]
        return PlayerViewDTO(
            gameId: id,
            joinCode: joinCode,
            phase: phase,
            phaseRemainingS: phase == .headStart ? 60 : nil,
            gameElapsedS: 0,
            timeLimitRemainingS: 1800,
            you: YouDTO(
                playerId: you.id,
                role: you.role,
                status: you.status,
                isHost: youAreHost,
                bounds: BoundsDTO(phase: "inside", remainingS: nil),
                safeZone: nil,
                points: you.points
            ),
            players: players.map {
                PlayerDTO(
                    playerId: $0.id,
                    displayName: $0.name,
                    role: $0.role,
                    status: $0.status,
                    isHost: $0.isHost,
                    location: nil
                )
            },
            reveals: [],
            banners: [],
            result: phase == .ended ? ResultDTO(winner: "seekers", reason: "Host ended.", endedAt: nil) : nil,
            tagMethod: tagMethod
        )
    }
}
