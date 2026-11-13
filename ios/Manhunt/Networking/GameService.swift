import Foundation

/// Client contract for REST game actions. Fake and live implementations share it.
protocol GameService: AnyObject {
    var joinCalls: Int { get }

    func signIn(displayName: String) async throws -> AuthOut
    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthOut
    func registerDeviceToken(_ token: String) async throws
    func arenas() async throws -> [Arena]
    func createArena(_ arena: Arena) async throws -> Arena
    func updateArena(_ arena: Arena) async throws -> Arena
    func deleteArena(id: UUID) async throws
    func createGame(arenaID: UUID, presetID: String, overrides: [String: [String: RuleValue]]) async throws -> PlayerViewDTO
    func timeline(gameID: UUID) async throws -> [TimelineEventDTO]
    func join(code: String) async throws -> PlayerViewDTO
    func randomizeRoles(gameID: UUID, seekerCount: Int) async throws -> PlayerViewDTO
    func setRole(gameID: UUID, playerID: UUID, role: PlayerRole) async throws -> PlayerViewDTO
    func start(gameID: UUID) async throws -> PlayerViewDTO
    func pause(gameID: UUID) async throws -> PlayerViewDTO
    func resume(gameID: UUID) async throws -> PlayerViewDTO
    func end(gameID: UUID) async throws -> PlayerViewDTO
    func leave(gameID: UUID) async throws
    func removePlayer(gameID: UUID, playerID: UUID) async throws -> PlayerViewDTO
    func undoTag(gameID: UUID) async throws -> PlayerViewDTO
    func ackSafety(gameID: UUID) async throws -> PlayerViewDTO
    func taunt(gameID: UUID) async throws -> PlayerViewDTO
    func view(gameID: UUID) async throws -> PlayerViewDTO
    func claimQR(gameID: UUID, token: String) async throws
    func claimUWB(gameID: UUID, hiderID: UUID) async throws
    func purchase(gameID: UUID, powerID: String, extra: [String: Double]) async throws -> PlayerViewDTO
    func demo(gameID: UUID, action: String, params: [String: RuleValue]) async throws -> PlayerViewDTO
    func fetchModules() async throws -> [VisualModule]
    func savePreset(name: String, modules: [String: [String: RuleValue]]) async throws -> SavedPresetDTO
    func updatePreset(id: String, name: String, modules: [String: [String: RuleValue]]) async throws -> SavedPresetDTO
    func deletePreset(id: String) async throws
    func savedPresets() async throws -> [SavedPresetDTO]
    func refresh(refreshToken: String) async throws -> AuthOut
}

struct SavedPresetDTO: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var modules: [String: [String: RuleValue]]
}

struct SavePresetBody: Encodable {
    var name: String
    var modules: [String: [String: RuleValue]]
}
