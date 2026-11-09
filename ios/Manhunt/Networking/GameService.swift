import Foundation

/// Client contract for REST game actions. Fake and live implementations share it.
protocol GameService: AnyObject {
    var joinCalls: Int { get }

    func signIn(displayName: String) async throws -> AuthOut
    func signInWithApple(identityToken: String, displayName: String?) async throws -> AuthOut
    func registerDeviceToken(_ token: String) async throws
    func arenas() async throws -> [Arena]
    func createArena(_ arena: Arena) async throws -> Arena
    func createGame(arenaID: UUID, presetID: String, overrides: [String: [String: RuleValue]]) async throws -> PlayerViewDTO
    func timeline(gameID: UUID) async throws -> [TimelineEventDTO]
    func join(code: String) async throws -> PlayerViewDTO
    func randomizeRoles(gameID: UUID, hiderCount: Int) async throws -> PlayerViewDTO
    func setRole(gameID: UUID, playerID: UUID, role: PlayerRole) async throws -> PlayerViewDTO
    func start(gameID: UUID) async throws -> PlayerViewDTO
    func pause(gameID: UUID) async throws -> PlayerViewDTO
    func resume(gameID: UUID) async throws -> PlayerViewDTO
    func end(gameID: UUID) async throws -> PlayerViewDTO
    func view(gameID: UUID) async throws -> PlayerViewDTO
    func claimQR(gameID: UUID, token: String) async throws
    func purchase(gameID: UUID, powerID: String, extra: [String: Double]) async throws -> PlayerViewDTO
}
