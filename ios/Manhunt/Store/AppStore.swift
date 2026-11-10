import CoreLocation
import Foundation
import UIKit

enum AppScreen: String, Equatable {
    case signedOut
    case home
    case createGame
    case lobby
    case live
    case results
    case arenaEditor
    case preset
}

enum AppError: Equatable {
    case missingArena
    case needBothRoles
    case invalidFormat
    case notFound
    case unreachable
    case service(ErrorCode)
}

struct Session: Equatable {
    var displayName: String
    var token: String
}

struct MatchHandle {
    var snapshot: PlayerViewDTO
    var qrToken: String?
}

@MainActor
@Observable
final class AppStore {
    var screen: AppScreen = .signedOut
    var session: Session?
    var match: MatchHandle?
    var lastError: AppError?
    var arenas: [Arena] = []
    var presets: [(id: String, name: String)] = [("classic", "Classic Manhunt")]
    var displayName = "Casey Lee"
    var serverURL: String
    var joinDraft = ""
    var joinMessage: String?
    var note: String?
    var hiderCount = 1
    var editor = ArenaEditorModel()
    var situation: LiveSituation = .active
    var radarOn = false
    var armedPowerUps: [String] = []
    var tool: ArenaTool = .playArea
    var draftBoundary: [VisualPoint] = []
    var draftZones: [VisualZone] = []
    var arenaID = SamplePark.riverside.id
    var paused = false
    var modules: [VisualModule] = SamplePark.classicModules()
    var locationAccuracy: LocationReporter.Accuracy = .notDetermined
    var pasteToken = ""
    var tagMessage: String?
    var timeline: [TimelineEventDTO] = []
    var uwbPeers: [UWBPeer] = []
    var uwbDistance: [UUID: Double] = [:]
    private var presetReturn: AppScreen = .home
    private var sentLowBattery = false
    private var lastSentLocation: CLLocation?

    private let service: GameService
    private let fake: FakeGameService?
    private let live: LiveGameService?
    private let ranger: UWBRanging
    private let keychain = KeychainStore()
    private let location = LocationReporter()
    private let defaults: UserDefaults
    private var uwbTokenFor: UUID?

    static let serverURLKey = "manhunt.serverURL"

    init(
        service: GameService,
        serverURL: String = AppStore.defaultServerURL(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.fake = service as? FakeGameService
        let liveService = service as? LiveGameService
        self.live = liveService
        self.ranger = UWBRangers.make(enabled: liveService != nil)
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.serverURLKey), !stored.isEmpty {
            self.serverURL = stored
        } else {
            self.serverURL = serverURL
        }
        if let fake {
            arenas = fake.storedArenas
        }
        location.onUpdate = { [weak self] loc in
            self?.sendFix(from: loc, isFinal: false)
        }
        location.onAccuracy = { [weak self] accuracy in
            self?.locationAccuracy = accuracy
        }
        live?.onView = { [weak self] view in
            self?.apply(view)
        }
        live?.onQR = { [weak self] token in
            self?.match?.qrToken = token
        }
        live?.onEvent = { [weak self] banner in
            self?.note = banner.detail
        }
        live?.onReconnect = { [weak self] reconnecting in
            if reconnecting { self?.situation = .reconnecting }
        }
        live?.onUWBPeers = { [weak self] peers in
            self?.applyUWBPeers(peers)
        }
        ranger.onDistance = { [weak self] id, meters in
            Task { @MainActor in
                self?.noteUWBDistance(id: id, meters: meters)
            }
        }
        let seeded = ProcessInfo.processInfo.environment["MANHUNT_SCREEN"]
        if let seeded, let mapped = AppScreen.fromLaunch(seeded) {
            screen = mapped
            if mapped != .signedOut {
                session = Session(displayName: "Casey Lee", token: "preview")
            }
        }
    }

    static func makePreview() -> AppStore {
        AppStore(service: FakeGameService())
    }

    static func makeForLaunch() -> AppStore {
        if ProcessInfo.processInfo.environment["MANHUNT_SCREEN"] != nil {
            return makePreview()
        }
        return makeLive()
    }

    static func makeLive() -> AppStore {
        let url = URL(string: AppStore.defaultServerURL()) ?? URL(string: "http://localhost:8000")!
        return AppStore(service: LiveGameService(baseURL: url), serverURL: url.absoluteString)
    }

    nonisolated static func defaultServerURL() -> String {
        Bundle.main.object(forInfoDictionaryKey: "ManhuntAPIBaseURL") as? String
            ?? "http://localhost:8000"
    }

    var isHost: Bool { match?.snapshot.you.isHost ?? false }
    var joinCode: String { match?.snapshot.joinCode ?? "" }
    var hostName: String {
        match?.snapshot.players.first(where: \.isHost)?.displayName ?? "The host"
    }

    var players: [VisualPlayer] {
        guard let match else { return SamplePark.players }
        return match.snapshot.players.map { player in
            let point: VisualPoint
            if let loc = player.location {
                point = VisualPoint(latitude: loc.lat, longitude: loc.lon)
            } else {
                point = VisualPoint(latitude: 40.6616, longitude: -73.9688)
            }
            return VisualPlayer(
                id: player.playerId.uuidString,
                name: player.displayName,
                role: visualRole(player.role),
                isYou: player.playerId == match.snapshot.you.playerId,
                isHost: player.isHost,
                point: point,
                points: player.playerId == match.snapshot.you.playerId ? match.snapshot.you.points : 0
            )
        }
    }

    var viewingRole: VisualRole {
        switch match?.snapshot.you.role {
        case .hider: return .hider
        case .seeker: return .seeker
        default: return .seeker
        }
    }

    var shownPoints: Int { match?.snapshot.you.points ?? 120 }

    var arena: VisualArena {
        if let selected = arenas.first(where: { $0.id.uuidString == arenaID }) {
            return selected.asVisual(place: selected.name)
        }
        if let match, let found = arenas.first(where: { $0.id == match.snapshot.gameId }) {
            return found.asVisual()
        }
        return SamplePark.riverside
    }

    var liveZones: [VisualZone] {
        var zones = arena.zones
        if let reveals = match?.snapshot.reveals {
            zones += reveals.map { pin in
                VisualZone(
                    id: pin.revealId.uuidString,
                    name: "Reveal",
                    kind: .safe,
                    points: [VisualPoint(latitude: pin.lat, longitude: pin.lon)],
                    radiusMeters: pin.radiusM
                )
            }
        }
        return zones
    }

    var livePeople: [VisualPlayer] {
        players.filter { player in
            player.isYou || match?.snapshot.players.first(where: { $0.playerId.uuidString == player.id })?.location != nil
        }
    }

    var editorIssues: [String] {
        editor.issues.map { issue in
            switch issue {
            case .playAreaTooSmall: return "Play area needs at least three points."
            case let .selfIntersection(name): return "\(name) crosses itself."
            case let .outsidePlayArea(name): return "\(name) leaves the play area."
            }
        }
    }

    func signInPreview() {
        fake?.signInSync("Casey Lee")
        session = Session(displayName: "Casey Lee", token: "preview")
        displayName = "Casey Lee"
        screen = .home
    }

    func signIn() {
        lastError = nil
        note = nil
        defaults.set(serverURL, forKey: Self.serverURLKey)
        if let fake {
            fake.signInSync(displayName)
            session = Session(displayName: displayName, token: "fake")
            screen = .home
            return
        }
        note = WakeCopy.message
        Task { await signInRemote() }
    }

    func signInWithApple(identityToken: String) {
        lastError = nil
        defaults.set(serverURL, forKey: Self.serverURLKey)
        if let fake {
            Task {
                _ = try? await fake.signInWithApple(identityToken: identityToken, displayName: displayName)
            }
            session = Session(displayName: displayName, token: "fake")
            screen = .home
            return
        }
        note = WakeCopy.message
        Task { await signInRemoteApple(identityToken: identityToken) }
    }

    /// Best-effort last ping when the hunt is backgrounded or the host ends it.
    func handleScenePhase(isBackground: Bool) {
        if isBackground, screen == .live {
            sendFinalPing()
        }
    }

    func sendFix(from location: CLLocation, isFinal: Bool, battery: Float? = nil) {
        lastSentLocation = location
        let level = battery ?? UIDevice.current.batteryLevel
        let choice = LocationFlag.choose(battery: level, isFinal: isFinal, wasLow: sentLowBattery)
        sentLowBattery = choice.nowLow
        live?.sendLocation(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            flag: choice.flag,
            battery: level >= 0 ? level : nil
        )
        fake?.recordLocationFlag(choice.flag)
    }

    func sendFinalPing() {
        guard let fix = lastSentLocation ?? location.lastFix else { return }
        sendFix(from: fix, isFinal: true)
    }

    func signOut() {
        stopUWB()
        live?.disconnect()
        location.stop()
        keychain.deleteToken()
        session = nil
        match = nil
        screen = .signedOut
        joinDraft = ""
        joinMessage = nil
        note = nil
    }

    func goHome() {
        stopUWB()
        screen = .home
    }
    func openCreate() { screen = .createGame }
    func openPreset() {
        presetReturn = screen == .preset ? presetReturn : screen
        screen = .preset
    }

    func closePreset() {
        screen = presetReturn == .preset ? .home : presetReturn
    }

    func openLobbyAsHost() {
        let id = selectedArenaID() ?? arenas.first?.id
        guard let id else {
            lastError = .missingArena
            return
        }
        createMatch(arenaID: id, presetID: presets[0].id)
    }

    func createMatch(arenaID: UUID, presetID: String) {
        lastError = nil
        if !arenas.contains(where: { $0.id == arenaID }) {
            lastError = .missingArena
            return
        }
        guard let fake else {
            let overrides = PresetOverrides.from(modules: modules)
            Task { await createMatchRemote(arenaID: arenaID, presetID: presetID, overrides: overrides) }
            return
        }
        do {
            let view = try fake.createGameSync(arenaID: arenaID, presetID: presetID)
            apply(view)
            screen = .lobby
        } catch {
            lastError = .missingArena
        }
    }

    func join() {
        _ = join(code: joinDraft)
    }

    @discardableResult
    func join(code: String) -> AppError? {
        lastError = nil
        let normalized = JoinCode.normalize(code)
        guard JoinCode.isValid(normalized) else {
            lastError = .invalidFormat
            joinMessage = "Codes are 6 characters."
            return .invalidFormat
        }
        guard let fake else {
            joinDraft = normalized
            Task { await joinRemote(normalized) }
            return nil
        }
        do {
            let view = try fake.joinSync(code: normalized)
            apply(view)
            screen = .lobby
            joinMessage = nil
            return nil
        } catch {
            lastError = .notFound
            joinMessage = "No game is using \(normalized)."
            return .notFound
        }
    }

    func randomizeRoles() {
        randomizeRoles(hiderCount: hiderCount)
    }

    func randomizeRoles(hiderCount: Int) {
        guard let id = match?.snapshot.gameId else { return }
        if let fake, let view = try? fake.randomizeRolesSync(gameID: id, hiderCount: hiderCount) {
            apply(view)
            return
        }
        Task {
            if let view = try? await service.randomizeRoles(gameID: id, hiderCount: hiderCount) {
                apply(view)
            }
        }
    }

    func cycleRole(_ id: String) {
        guard isHost, let uuid = UUID(uuidString: id), var snapshot = match?.snapshot,
              let index = snapshot.players.firstIndex(where: { $0.playerId == uuid })
        else { return }
        let next: PlayerRole
        switch snapshot.players[index].role {
        case .hider: next = .seeker
        case .seeker: next = .unassigned
        case .unassigned: next = .hider
        }
        snapshot.players[index].role = next
        match?.snapshot = snapshot
        if let fake, let gameID = match?.snapshot.gameId,
           let view = try? fake.setRoleSync(gameID: gameID, playerID: uuid, role: next)
        {
            apply(view)
        }
    }

    @discardableResult
    func startMatch() -> AppError? {
        guard let id = match?.snapshot.gameId else { return .service(.gameNotFound) }
        guard let fake else {
            Task { await startRemote() }
            return nil
        }
        do {
            let view = try fake.startSync(gameID: id)
            apply(view)
            enterLive()
            return nil
        } catch let error as ServiceError where error.code == .needBothRoles {
            lastError = .needBothRoles
            return .needBothRoles
        } catch {
            lastError = .service(.internal)
            return .service(.internal)
        }
    }

    func startLive() { _ = startMatch() }

    func endMatch() {
        if let fake, let id = match?.snapshot.gameId, let view = try? fake.endSync(gameID: id) {
            apply(view)
        } else if let id = match?.snapshot.gameId {
            Task {
                if let view = try? await service.end(gameID: id) { apply(view) }
            }
        }
        sendFinalPing()
        stopUWB()
        location.stop()
        live?.disconnect()
        screen = .results
        Task { await loadTimeline() }
    }

    func endLive() { endMatch() }

    func pauseOrResume() {
        paused.toggle()
        guard let id = match?.snapshot.gameId, live != nil else { return }
        Task {
            if paused {
                if let view = try? await service.pause(gameID: id) { apply(view) }
            } else {
                if let view = try? await service.resume(gameID: id) { apply(view) }
            }
        }
    }

    func leaveResults() {
        match = nil
        screen = .home
    }

    func editArena(_ id: String) {
        arenaID = id
        if let uuid = UUID(uuidString: id), let arena = arenas.first(where: { $0.id == uuid }) {
            loadEditor(from: arena)
        } else if let sample = SamplePark.arenas.first(where: { $0.id == id }) {
            draftBoundary = sample.boundary
            draftZones = sample.zones
        }
        screen = .arenaEditor
    }

    func beginNewArena() {
        arenaID = "new"
        editor = ArenaEditorModel()
        draftBoundary = []
        draftZones = []
        screen = .arenaEditor
    }

    func drop(at point: VisualPoint) {
        editor.tool = editorTool(from: tool)
        editor.addMapPoint(GeoPoint(latitude: point.latitude, longitude: point.longitude))
        refreshDraftsFromEditor()
    }

    func undoDrop() {
        editor.undo()
        refreshDraftsFromEditor()
    }

    func saveArena() {
        var arena = Arena(
            id: UUID(),
            name: arenaID == "new" ? "New arena" : arena.name,
            boundary: editor.boundary,
            zones: editor.zones
        )
        if !editor.issues.isEmpty {
            note = editorIssues.joined(separator: " ")
            return
        }
        Task {
            do {
                arena = try await service.createArena(arena)
                arenas.append(arena)
                note = "Arena saved."
                screen = .home
            } catch {
                note = "Could not save the arena. Is the home server running?"
            }
        }
    }

    func buyPower(_ chip: PowerChip) {
        togglePower(chip)
        guard let id = match?.snapshot.gameId else { return }
        Task {
            if let view = try? await service.purchase(gameID: id, powerID: chip.id, extra: [:]) {
                apply(view)
            }
        }
    }

    func togglePower(_ chip: PowerChip) {
        if armedPowerUps.contains(chip.id) {
            armedPowerUps.removeAll { $0 == chip.id }
            if chip.id == "radar" { radarOn = false }
            return
        }
        guard shownPoints >= chip.cost else {
            note = "Not enough points for \(chip.title)."
            return
        }
        armedPowerUps.append(chip.id)
        note = "\(chip.title) armed. \(chip.detail)."
        if chip.id == "radar" { radarOn = true }
    }

    func claimUWB(hiderID: UUID) {
        tagMessage = nil
        guard let id = match?.snapshot.gameId else { return }
        Task {
            do {
                try await service.claimUWB(gameID: id, hiderID: hiderID)
                tagMessage = "Tag accepted."
            } catch let error as ServiceError {
                tagMessage = Self.copy(for: error.code)
            } catch {
                tagMessage = "Could not send the tag."
            }
        }
    }

    func applyUWBPeers(_ peers: [UWBPeer]) {
        let ids = Set(peers.map(\.id))
        uwbDistance = uwbDistance.filter { ids.contains($0.key) }
        uwbPeers = peers
        ranger.setPeers(peers)
    }

    func noteUWBDistance(id: UUID, meters: Double) {
        uwbDistance[id] = meters
        live?.sendUWBRange(peerID: id, distanceM: meters)
    }

    private func publishUWBTokenIfNeeded() {
        guard let live, match?.snapshot.tagMethod == "uwb", let gameID = match?.snapshot.gameId else { return }
        guard uwbTokenFor != gameID, let token = ranger.localToken() else { return }
        live.sendUWBToken(token)
        uwbTokenFor = gameID
    }

    private func stopUWB() {
        ranger.stop()
        uwbPeers = []
        uwbDistance = [:]
        uwbTokenFor = nil
    }

    func submitQR(_ token: String) {
        tagMessage = nil
        guard let id = match?.snapshot.gameId else { return }
        Task {
            do {
                try await service.claimQR(gameID: id, token: token)
                tagMessage = "Tag accepted."
            } catch let error as ServiceError {
                tagMessage = Self.copy(for: error.code)
            } catch {
                tagMessage = "Could not send the tag."
            }
        }
    }

    static func copy(for code: ErrorCode) -> String {
        switch code {
        case .notInPairingRange: return "Get closer. GPS says you are too far to tag."
        case .notInRange: return "Ultra Wideband says you are still out of tag range."
        case .targetShielded: return "That hider has a shield up."
        case .targetInSafeZone: return "They are in a safe zone."
        case .tokenInvalid, .tokenExpired: return "That code is stale. Scan again."
        case .wrongRole: return "Only seekers can tag."
        case .eliminated, .targetNotActive: return "That player is already out."
        case .wrongPhase: return "Tags are closed during this phase."
        default: return "The tag did not go through (\(code.rawValue))."
        }
    }

    func apply(_ view: PlayerViewDTO) {
        match = MatchHandle(snapshot: view, qrToken: match?.qrToken)
        publishUWBTokenIfNeeded()
        switch view.phase {
        case .ended:
            location.stop()
            live?.disconnect()
            screen = .results
            Task { await loadTimeline() }
        case .headStart:
            situation = .headStart
            paused = false
        case .paused:
            paused = true
            situation = .active
        case .active:
            paused = false
            if view.you.bounds.phase != "inside" {
                situation = .outOfBounds
            } else if view.you.status == .signalLost {
                situation = .signalLost
            } else if situation == .reconnecting {
                situation = .active
            } else {
                situation = .active
            }
        case .lobby:
            break
        }
        if view.you.bounds.phase != "inside", view.phase == .active || view.phase == .headStart {
            situation = .outOfBounds
        }
        if !view.banners.isEmpty {
            note = view.banners.last?.detail
        }
    }

    private func enterLive() {
        screen = .live
        location.start()
        if let id = match?.snapshot.gameId {
            live?.connect(gameID: id)
        }
    }

    private func signInRemote() async {
        live?.updateBaseURL(URL(string: serverURL) ?? URL(string: "http://localhost:8000")!)
        do {
            let auth = try await service.signIn(displayName: displayName)
            await finishRemoteAuth(auth)
        } catch {
            lastError = .unreachable
            note = "Is the home server running? Could not reach \(serverURL)."
        }
    }

    private func signInRemoteApple(identityToken: String) async {
        live?.updateBaseURL(URL(string: serverURL) ?? URL(string: "http://localhost:8000")!)
        do {
            let auth = try await service.signInWithApple(
                identityToken: identityToken,
                displayName: displayName
            )
            await finishRemoteAuth(auth)
        } catch {
            lastError = .unreachable
            note = "Is the home server running? Could not reach \(serverURL)."
        }
    }

    private func finishRemoteAuth(_ auth: AuthOut) async {
        try? keychain.saveToken(auth.accessToken)
        session = Session(displayName: auth.user.displayName, token: auth.accessToken)
        displayName = auth.user.displayName
        note = nil
        if let loaded = try? await service.arenas() { arenas = loaded }
        screen = .home
        // TODO: register the APNs device token with PUT /v1/me/device-token
        // once the paid team adds the Push Notifications entitlement.
    }

    func loadTimeline() async {
        guard let id = match?.snapshot.gameId else { return }
        if let events = try? await service.timeline(gameID: id) {
            timeline = events
        }
    }

    private func createMatchRemote(
        arenaID: UUID,
        presetID: String,
        overrides: [String: [String: RuleValue]]
    ) async {
        do {
            let view = try await service.createGame(arenaID: arenaID, presetID: presetID, overrides: overrides)
            apply(view)
            screen = .lobby
            live?.connect(gameID: view.gameId)
        } catch let error as ServiceError where error.code == .arenaNotFound {
            lastError = .missingArena
        } catch {
            lastError = .unreachable
            note = "Is the home server running?"
        }
    }

    private func joinRemote(_ code: String) async {
        do {
            let view = try await service.join(code: code)
            apply(view)
            screen = .lobby
            joinMessage = nil
            live?.connect(gameID: view.gameId)
        } catch {
            lastError = .notFound
            joinMessage = "No game is using \(code)."
        }
    }

    private func startRemote() async {
        guard let id = match?.snapshot.gameId else { return }
        do {
            let view = try await service.start(gameID: id)
            apply(view)
            enterLive()
        } catch let error as ServiceError where error.code == .needBothRoles {
            lastError = .needBothRoles
        } catch {
            lastError = .service(.internal)
        }
    }

    private func selectedArenaID() -> UUID? {
        if let uuid = UUID(uuidString: arenaID) { return uuid }
        if arenaID == SamplePark.riverside.id { return Arena.riversideID }
        if arenaID == SamplePark.schoolyard.id { return Arena.schoolyardID }
        return nil
    }

    private func loadEditor(from arena: Arena) {
        editor = ArenaEditorModel()
        editor.tool = .playArea
        for point in arena.boundary.vertices {
            editor.addMapPoint(point)
        }
        editor.zones = arena.zones
        refreshDraftsFromEditor()
    }

    private func refreshDraftsFromEditor() {
        draftBoundary = editor.boundary.vertices.map {
            VisualPoint(latitude: $0.latitude, longitude: $0.longitude)
        }
        draftZones = editor.zones.map { $0.asVisual() }
    }

    private func editorTool(from tool: ArenaTool) -> EditorTool {
        switch tool {
        case .playArea: return .playArea
        case .safe: return .safeCircle
        case .outOfBounds: return .outOfBounds
        case .spawn: return .seekerSpawn
        }
    }

    private func visualRole(_ role: PlayerRole) -> VisualRole {
        switch role {
        case .hider: return .hider
        case .seeker: return .seeker
        case .unassigned: return .unassigned
        }
    }
}

private extension AppScreen {
    static func fromLaunch(_ raw: String) -> AppScreen? {
        switch raw {
        case "signIn": return .signedOut
        case "home": return .home
        case "create": return .createGame
        case "lobby": return .lobby
        case "live": return .live
        case "results": return .results
        case "arena": return .arenaEditor
        case "preset": return .preset
        default: return AppScreen(rawValue: raw)
        }
    }
}
