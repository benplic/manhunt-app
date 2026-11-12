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
    /// Decoy purchase step: pan the map and drop a pin before POST.
    var decoyPicking = false
    var tool: ArenaTool = .playArea
    var draftBoundary: [VisualPoint] = []
    var draftBoundaryCircle: CircleBoundary?
    var draftZones: [VisualZone] = []
    var draftPending: [VisualPoint] = []
    var draftCircleCenter: VisualPoint?
    var draftCrosshair: VisualPoint?
    var draftHighlightedEdge: (VisualPoint, VisualPoint)?
    var editorHomeCoordinate: CLLocationCoordinate2D?
    /// Incremented once so HuntMap reframes after the permission sheet, not on every GPS tick.
    var editorFrameID = 0
    private var awaitingEditorFrame = false
    var editingPresetID: String?
    var arenaID = SamplePark.riverside.id
    var paused = false
    var modules: [VisualModule] = SamplePark.classicModules()
    var presetName = "Park night"
    var savedPresets: [SavedPresetDTO] = []
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
    /// Last discovery token pushed to the server. Cleared on reconnect so a
    /// rebuilt session gets a fresh publish. Compared by value so a rotated
    /// local token is resent even mid-match.
    private var lastUWBToken: String?
    private var lastUWBRangeAt: [UUID: Date] = [:]
    /// APNs device token waiting for auth, then PUT /v1/me/device-token.
    private var pendingDeviceToken: String?

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
            guard let self else { return }
            sendFix(from: loc, isFinal: false)
            receiveEditorFix(loc.coordinate)
        }
        location.onAccuracy = { [weak self] accuracy in
            self?.locationAccuracy = accuracy
        }
        location.onAuthorizationChange = { [weak self] accuracy in
            self?.noteLocationAuthorization(accuracy)
        }
        // Socket callbacks arrive off the main actor. The store is @MainActor,
        // so a direct call never moves the other phone off the lobby.
        live?.onView = { [weak self] view in
            Task { @MainActor in
                self?.apply(view)
            }
        }
        live?.onQR = { [weak self] token in
            Task { @MainActor in
                self?.match?.qrToken = token
            }
        }
        live?.onEvent = { [weak self] banner in
            Task { @MainActor in
                guard let self else { return }
                // The locked map already says to wait. Keeping this line makes it
                // pop up again when head start ends.
                if banner.title == "started" { return }
                // A toast from a hunt that already ended must not land on Home.
                guard self.match != nil, self.screen == .live || self.screen == .lobby else { return }
                self.note = banner.detail
            }
        }
        live?.onReconnect = { [weak self] reconnecting in
            Task { @MainActor in
                guard let self, reconnecting else { return }
                self.situation = .reconnecting
                // Server restart drops tokens. Force a republish on the next view.
                self.lastUWBToken = nil
            }
        }
        live?.onUWBPeers = { [weak self] peers in
            self?.applyUWBPeers(peers)
        }
        live?.onSendFailure = { [weak self] _ in
            Task { @MainActor in
                self?.situation = .reconnecting
                self?.note = "Connection hiccup. Retrying…"
            }
        }
        live?.onRefreshFailed = { [weak self] in
            self?.signOut()
            self?.note = "Session expired. Sign in again."
        }
        live?.onTokensRotated = { [weak self] auth in
            try? self?.keychain.saveToken(auth.accessToken)
            if let refresh = auth.refreshToken {
                try? self?.keychain.saveRefreshToken(refresh)
            }
            if let session = self?.session {
                self?.session = Session(displayName: session.displayName, token: auth.accessToken)
            }
        }
        // Cold start: restore refresh so a 401 can rotate without forcing sign-in.
        if let live, let storedRefresh = keychain.readRefreshToken() {
            live.refreshToken = storedRefresh
        }
        if let live, let storedAccess = keychain.readToken() {
            live.token = storedAccess
        }
        location.onStreamFailure = { [weak self] in
            self?.situation = .reconnecting
            self?.note = "Location stream dropped. Reconnecting…"
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
                points: player.points
                    ?? (player.playerId == match.snapshot.you.playerId ? match.snapshot.you.points : 0)
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

    /// True while the server radar effect is live on `you.effects`.
    var radarShowsSeekers: Bool {
        match?.snapshot.you.effects?.contains("radar") == true
    }

    /// Hider map: radar effect, or any seeker location the filtered view already sent
    /// (out-of-bounds reveal). Never invents pins from a rejected purchase.
    var shouldShowSeekerPins: Bool {
        if radarShowsSeekers { return true }
        return livePeople.contains { $0.role == .seeker && !$0.isYou }
    }

    /// Boundary and zones for the hunt on screen. The server snapshot wins.
    var mapArena: VisualArena {
        MatchMap.arena(snapshot: match?.snapshot.arena, local: arena)
    }

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
        var zones = mapArena.zones
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

    /// One orange line: the latest editor notice, otherwise the first blocking issue.
    var editorWarning: String? {
        if let notice = editor.notice, !notice.isEmpty { return notice }
        return editorIssues.first
    }

    var isSavingArena = false
    var isSavingPreset = false

    var editorIssues: [String] {
        editor.issues.map { issue in
            switch issue {
            case .playAreaTooSmall: return "Play area needs at least three points."
            case .playAreaRadiusInvalid: return "Play area radius must be between 30 m and 2,000 m."
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
        Task { await registerPendingDeviceTokenIfNeeded() }
    }

    func signIn() {
        lastError = nil
        note = nil
        defaults.set(serverURL, forKey: Self.serverURLKey)
        if let fake {
            fake.signInSync(displayName)
            session = Session(displayName: displayName, token: "fake")
            screen = .home
            Task { await registerPendingDeviceTokenIfNeeded() }
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
                await registerPendingDeviceTokenIfNeeded()
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
        live?.refreshToken = nil
        location.stop()
        keychain.deleteToken()
        session = nil
        match = nil
        screen = .signedOut
        joinDraft = ""
        joinMessage = nil
        note = nil
    }

    /// Leave the current lobby/hunt (POST /leave) then return home.
    func goHome() {
        leaveMatchThenHome()
    }

    func leaveMatchThenHome() {
        let gameID = match?.snapshot.gameId
        stopUWB()
        location.stop()
        live?.disconnect()
        match = nil
        screen = .home
        note = nil
        guard let gameID else { return }
        Task {
            try? await service.leave(gameID: gameID)
        }
    }
    func openCreate() { screen = .createGame }
    func openPreset() {
        presetReturn = screen == .preset ? presetReturn : screen
        // Load the schema before the form appears. Replacing `modules` under a
        // visible segmented picker crashes SwiftUI with an index-out-of-range trap.
        Task {
            await refreshPresetEditor()
            screen = .preset
        }
    }

    func refreshPresetEditor() async {
        // Keep the host's in-memory edits. Replacing wholesale wiped them every
        // time the editor reopened.
        if let remote = try? await service.fetchModules(), !remote.isEmpty {
            let current = PresetOverrides.from(modules: modules)
            modules = ModuleForm.apply(current, to: remote)
        }
        if let saved = try? await service.savedPresets() {
            savedPresets = saved
        }
    }

    func savePreset() async {
        if isSavingPreset { return }
        isSavingPreset = true
        defer { isSavingPreset = false }
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "Custom" : name
        let overrides = PresetOverrides.from(modules: modules)
        do {
            let saved: SavedPresetDTO
            if let editingPresetID {
                saved = try await service.updatePreset(
                    id: editingPresetID,
                    name: title,
                    modules: overrides
                )
            } else {
                saved = try await service.savePreset(name: title, modules: overrides)
            }
            savedPresets.removeAll { $0.id == saved.id }
            savedPresets.insert(saved, at: 0)
            editingPresetID = saved.id
            note = "Saved \(saved.name)."
        } catch let error as ServiceError {
            note = error.message
        } catch {
            note = "Could not save the preset."
        }
    }

    func applySavedPreset(_ preset: SavedPresetDTO) {
        loadPreset(preset)
    }

    func loadPreset(_ preset: SavedPresetDTO) {
        modules = ModuleForm.apply(preset.modules, to: modules)
        presetName = preset.name
        editingPresetID = preset.id
        note = "Loaded \(preset.name)."
    }

    func beginNewPreset() {
        editingPresetID = nil
        presetName = ""
        modules = ModuleForm.offlineModules()
        note = nil
    }

    func deletePreset(id: String) {
        Task {
            do {
                try await service.deletePreset(id: id)
                savedPresets.removeAll { $0.id == id }
                if editingPresetID == id {
                    beginNewPreset()
                }
                note = "Preset deleted."
            } catch {
                note = "Could not delete the preset."
            }
        }
    }

    @discardableResult
    func open(url: URL) -> AppError? {
        guard let code = InviteLink.joinCode(from: url) else {
            lastError = .invalidFormat
            joinMessage = "That link is not a hunt invite."
            return .invalidFormat
        }
        return join(code: code)
    }

    func openInvite(_ payload: String) {
        guard let code = InviteLink.joinCode(fromQR: payload) else {
            lastError = .invalidFormat
            joinMessage = "That code is not a hunt invite."
            return
        }
        _ = join(code: code)
    }

    var inviteURL: URL? {
        let code = joinCode
        guard JoinCode.isValid(code) else { return nil }
        return InviteLink.url(joinCode: code)
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
        guard let selected = arenas.first(where: { $0.id == arenaID }) else {
            lastError = .missingArena
            return
        }
        // Keep the live map boundary in sync with the arena used for create.
        self.arenaID = arenaID.uuidString
        guard let fake else {
            let overrides = PresetOverrides.from(modules: modules, arena: selected)
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

    var selectedArena: Arena? {
        guard let id = selectedArenaID() else { return arenas.first }
        return arenas.first(where: { $0.id == id })
    }

    func applyRulePreset(_ preset: RulePreset) {
        var updated = modules
        preset.apply(to: &updated)
        modules = updated
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
        } catch let error as ServiceError {
            lastError = error.code == .gameNotFound ? .notFound : .service(error.code)
            joinMessage = error.message
            return error.code == .gameNotFound ? .notFound : .service(error.code)
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
              let index = snapshot.players.firstIndex(where: { $0.playerId == uuid }),
              let gameID = match?.snapshot.gameId
        else { return }
        let next: PlayerRole
        switch snapshot.players[index].role {
        case .hider: next = .seeker
        case .seeker: next = .unassigned
        case .unassigned: next = .hider
        }
        // Optimistic pill update; the service call is what the server starts from.
        snapshot.players[index].role = next
        match?.snapshot = snapshot
        lastError = nil
        note = nil
        if let fake {
            if let view = try? fake.setRoleSync(gameID: gameID, playerID: uuid, role: next) {
                apply(view)
            }
            return
        }
        Task {
            do {
                let view = try await service.setRole(gameID: gameID, playerID: uuid, role: next)
                apply(view)
            } catch {
                note = "Could not update that role. Try again."
                lastError = .service(.internal)
            }
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
            note = Self.needBothRolesCopy
            return .needBothRoles
        } catch {
            lastError = .service(.internal)
            note = "Could not start the hunt."
            return .service(.internal)
        }
    }

    func startLive() { _ = startMatch() }

    static let needBothRolesCopy = "Assign at least one hider and one seeker before starting."

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

    func undoLastTag() {
        guard isHost, let id = match?.snapshot.gameId else { return }
        Task {
            do {
                let view = try await service.undoTag(gameID: id)
                apply(view)
                note = "Last tag undone."
            } catch {
                note = "Could not undo the tag."
            }
        }
    }

    func acknowledgeSafety() {
        guard isHost, let id = match?.snapshot.gameId else { return }
        Task {
            do {
                let view = try await service.ackSafety(gameID: id)
                apply(view)
                note = "Safety alert acknowledged."
            } catch {
                note = "Could not acknowledge the safety alert."
            }
        }
    }

    func removeLobbyPlayer(_ id: String) {
        guard isHost, let gameID = match?.snapshot.gameId, let playerID = UUID(uuidString: id) else { return }
        Task {
            do {
                let view = try await service.removePlayer(gameID: gameID, playerID: playerID)
                apply(view)
                note = "Player removed."
            } catch {
                note = "Could not remove that player."
            }
        }
    }

    func taunt() {
        guard let id = match?.snapshot.gameId else { return }
        guard match?.snapshot.you.role == .hider, match?.snapshot.phase == .active else {
            note = "Taunt is only for hiders during the hunt."
            return
        }
        Task {
            do {
                let view = try await service.taunt(gameID: id)
                apply(view)
                note = "Taunt sent. Seekers can see you for a few seconds."
            } catch let error as ServiceError {
                note = Self.copy(for: error.code)
            } catch {
                note = "Could not taunt."
            }
        }
    }

    /// Stash an APNs device token until after sign-in, then register it.
    func setPendingDeviceToken(_ token: String) {
        pendingDeviceToken = token
        Task { await registerPendingDeviceTokenIfNeeded() }
    }

    func leaveResults() {
        match = nil
        note = nil
        screen = .home
    }

    func editArena(_ id: String) {
        arenaID = id
        if let uuid = UUID(uuidString: id), let arena = arenas.first(where: { $0.id == uuid }) {
            loadEditor(from: arena)
            editorHomeCoordinate = CLLocationCoordinate2D(
                latitude: EditorCamera.snapTarget(user: userGeoPoint).latitude,
                longitude: EditorCamera.snapTarget(user: userGeoPoint).longitude
            )
        } else if let sample = SamplePark.arenas.first(where: { $0.id == id }) {
            draftBoundary = sample.boundary
            draftBoundaryCircle = sample.boundaryCircle
            draftZones = sample.zones
        }
        screen = .arenaEditor
    }

    func beginNewArena() {
        arenaID = "new"
        editor = ArenaEditorModel()
        tool = .playArea
        draftCrosshair = nil
        draftBoundary = []
        draftZones = []
        refreshDraftsFromEditor()
        let snap = EditorCamera.snapTarget(user: userGeoPoint)
        editorHomeCoordinate = CLLocationCoordinate2D(latitude: snap.latitude, longitude: snap.longitude)
        if live != nil {
            location.requestFix()
        }
        awaitingEditorFrame = true
        screen = .arenaEditor
    }

    /// Permission sheet answered. Frame immediately when a fix is already in hand.
    func noteLocationAuthorization(_ accuracy: LocationReporter.Accuracy) {
        locationAccuracy = accuracy
        guard screen == .arenaEditor, awaitingEditorFrame else { return }
        let decision = EditorFraming.afterAuthorization(
            accuracy: accuracy,
            hasFix: location.lastFix != nil,
            boundaryCount: editor.boundary.vertices.count
        )
        if accuracy == .denied {
            awaitingEditorFrame = false
            return
        }
        if decision.frameNow, let fix = location.lastFix {
            receiveEditorFix(fix.coordinate)
        }
    }

    /// First fix for a new arena moves the camera once. Later fixes only update the home pin.
    func receiveEditorFix(_ coordinate: CLLocationCoordinate2D) {
        guard screen == .arenaEditor, editor.boundary.vertices.count < 3 else { return }
        editorHomeCoordinate = coordinate
        guard awaitingEditorFrame else { return }
        editorFrameID += 1
        awaitingEditorFrame = false
    }

    func updateEditorCrosshair(_ point: VisualPoint) {
        draftCrosshair = point
        let geo = GeoPoint(latitude: point.latitude, longitude: point.longitude)
        if let edge = editor.previewEdge(near: geo) {
            draftHighlightedEdge = (
                VisualPoint(latitude: edge.0.latitude, longitude: edge.0.longitude),
                VisualPoint(latitude: edge.1.latitude, longitude: edge.1.longitude)
            )
        } else {
            draftHighlightedEdge = nil
        }
    }

    func clearPlayArea() {
        editor.clearPlayArea()
        refreshDraftsFromEditor()
    }

    func drop(at point: VisualPoint) {
        editor.tool = editorTool(from: tool)
        editor.addMapPoint(GeoPoint(latitude: point.latitude, longitude: point.longitude))
        refreshDraftsFromEditor()
    }

    func selectPlayEdge(_ index: Int) {
        editor.selectEdge(index)
    }

    func selectPlayVertex(_ index: Int) {
        editor.selectVertex(index)
    }

    func deletePlayVertex(_ index: Int) {
        editor.deleteVertex(at: index)
        refreshDraftsFromEditor()
    }

    func beginNewZoneShape() {
        editor.beginNewShape()
        refreshDraftsFromEditor()
    }

    func renameZone(id: UUID, to name: String) {
        editor.renameZone(id: id, to: name)
        refreshDraftsFromEditor()
    }

    func deleteZone(id: UUID) {
        editor.deleteZone(id: id)
        refreshDraftsFromEditor()
    }

    /// Layers sheet: keep editing this polygon. Safe circles stay rename-and-delete only.
    func editZoneShape(id: UUID) {
        editor.editZone(id)
        tool = arenaTool(from: editor.tool)
    }

    func undoDrop() {
        editor.undo()
        refreshDraftsFromEditor()
    }

    func saveArena() {
        if isSavingArena { return }
        let trimmed = editor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "New arena" : trimmed
        var prepared = editor.preparedForSave()
        if !prepared.blocking.isEmpty {
            let text = issueCopy(prepared.blocking[0])
            editor.notice = text
            note = text
            return
        }
        // Editing an existing arena must PUT the same id. Creating always POSTs a new one.
        let existingID = UUID(uuidString: arenaID)
        let isUpdate = arenaID != "new"
            && existingID != nil
            && arenas.contains(where: { $0.id == existingID })
        var arena = prepared.arena
        arena.id = isUpdate ? existingID! : UUID()
        arena.name = name
        let warnings = prepared.warnings
        isSavingArena = true
        Task {
            defer { isSavingArena = false }
            do {
                let saved: Arena
                if isUpdate {
                    saved = try await service.updateArena(arena)
                    if let index = arenas.firstIndex(where: { $0.id == saved.id }) {
                        arenas[index] = saved
                    } else {
                        arenas.append(saved)
                    }
                } else {
                    saved = try await service.createArena(arena)
                    arenas.append(saved)
                }
                arenaID = saved.id.uuidString
                if warnings.isEmpty {
                    note = "Arena saved."
                } else {
                    note = warnings.joined(separator: " ") + " Arena saved."
                }
                screen = .home
            } catch let error as ServiceError {
                let text = arenaFailureText(error)
                editor.notice = text
                note = text
            } catch {
                let text = "Could not save the arena. Is the home server running?"
                editor.notice = text
                note = text
            }
        }
    }

    private func arenaFailureText(_ error: ServiceError) -> String {
        guard error.code == .arenaInvalid, let issue = error.issues.first else {
            return error.message
        }
        switch issue.code {
        case "self_intersection":
            return "\(issue.name ?? "A shape") crosses itself."
        case "outside_play_area":
            return "\(issue.name ?? "A zone") leaves the play area."
        case "too_many_zones":
            return "An arena can have at most 30 zones."
        case "play_area_too_small":
            return "Play area needs at least three points."
        case "play_area_radius_invalid":
            return "Play area radius must be between 30 m and 2,000 m."
        default:
            return error.message
        }
    }

    func renameArena(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var arena = arenas.first(where: { $0.id == id }) else { return }
        arena.name = trimmed
        Task {
            do {
                let saved = try await service.updateArena(arena)
                if let index = arenas.firstIndex(where: { $0.id == saved.id }) {
                    arenas[index] = saved
                }
                note = "Arena renamed."
            } catch {
                note = "Could not rename the arena."
            }
        }
    }

    func deleteArena(id: UUID) {
        Task {
            do {
                try await service.deleteArena(id: id)
                arenas.removeAll { $0.id == id }
                note = "Arena deleted."
            } catch {
                note = "Could not delete the arena."
            }
        }
    }

    func purchaseRequest(
        for chip: PowerChip,
        hasTarget: Bool = false,
        targetInsidePlayArea: Bool = true
    ) -> PurchaseRequest? {
        guard let snapshot = match?.snapshot else { return nil }
        return PurchaseRequest(
            balance: snapshot.you.points,
            cost: chip.cost,
            cooldownRemaining: snapshot.you.cooldowns?[chip.id] ?? 0,
            phase: snapshot.phase,
            role: snapshot.you.role,
            requiredRole: chip.role == .hider ? .hider : .seeker,
            status: snapshot.you.status,
            requiresTarget: chip.id == "decoy",
            hasTarget: hasTarget,
            targetInsidePlayArea: targetInsidePlayArea
        )
    }

    func powerChipDecision(
        for chip: PowerChip,
        hasTarget: Bool = false,
        targetInsidePlayArea: Bool = true
    ) -> PurchaseDecision? {
        guard let request = purchaseRequest(
            for: chip,
            hasTarget: hasTarget,
            targetInsidePlayArea: targetInsidePlayArea
        ) else { return nil }
        return PowerUpRules.decide(request)
    }

    func chipIsTappable(_ chip: PowerChip) -> Bool {
        guard let request = purchaseRequest(for: chip) else { return false }
        return PowerUpRules.chipIsTappable(request)
    }

    func buyPower(_ chip: PowerChip) {
        guard chipIsTappable(chip) else { return }
        if chip.id == "decoy" {
            decoyPicking = true
            note = "Pan the map, then drop a decoy inside the play area."
            return
        }
        let decision = powerChipDecision(for: chip)
        guard decision == .allowed else {
            note = denialNote(for: decision)
            return
        }
        submitPurchase(chip, extra: [:])
    }

    func cancelDecoyPick() {
        decoyPicking = false
        note = nil
    }

    func dropDecoy(at point: VisualPoint) {
        guard let chip = SamplePark.powerUps.first(where: { $0.id == "decoy" }) else { return }
        // Deny outside the yellow play area before POST. Server still re-checks
        // the session arena boundary; this keeps lat/lon off the wire when the
        // map the player sees already says the point is outside.
        let geo = GeoPoint(latitude: point.latitude, longitude: point.longitude)
        let inside = ArenaGeometry.contains(geo, in: playAreaPolygon())
        let decision = powerChipDecision(
            for: chip,
            hasTarget: true,
            targetInsidePlayArea: inside
        )
        guard decision == .allowed else {
            note = denialNote(for: decision)
            return
        }
        submitPurchase(chip, extra: ["lat": point.latitude, "lon": point.longitude], clearingDecoyPick: true)
    }

    /// Play area drawn on the live map (`HuntMap` boundary).
    private func playAreaPolygon() -> Polygon {
        Polygon(
            vertices: mapArena.boundary.map {
                GeoPoint(latitude: $0.latitude, longitude: $0.longitude)
            }
        )
    }

    private func submitPurchase(
        _ chip: PowerChip,
        extra: [String: Double],
        clearingDecoyPick: Bool = false
    ) {
        guard let id = match?.snapshot.gameId else { return }
        Task {
            do {
                let view = try await service.purchase(gameID: id, powerID: chip.id, extra: extra)
                apply(view)
                if clearingDecoyPick { decoyPicking = false }
                note = "\(chip.title) armed. \(chip.detail)."
            } catch let error as ServiceError {
                // Stay in pick mode on TARGET_OUTSIDE so the player can drop again.
                note = Self.purchaseCopy(for: error.code)
            } catch {
                note = "Could not buy \(chip.title)."
            }
        }
    }

    private func denialNote(for decision: PurchaseDecision?) -> String? {
        guard case let .denied(reason) = decision else { return nil }
        switch reason {
        case .insufficientPoints: return "Not enough points."
        case .coolingDown: return "That power-up is still cooling down."
        case .wrongPhase: return "Power-ups are only available during the hunt."
        case .wrongRole: return "Wrong role for that power-up."
        case .eliminated: return "You are out of this round."
        case .needsTarget: return "Pick a spot on the map first."
        case .targetOutside: return "Decoy has to sit inside the play area."
        }
    }

    static func purchaseCopy(for code: ErrorCode) -> String {
        switch code {
        case .insufficientPoints: return "Not enough points."
        case .coolingDown: return "That power-up is still cooling down."
        case .wrongPhase: return "Power-ups are only available during the hunt."
        case .wrongRole: return "Wrong role for that power-up."
        case .eliminated: return "You are out of this round."
        case .needsTarget: return "Pick a spot on the map first."
        case .targetOutside: return "Decoy has to sit inside the play area."
        default: return "Purchase did not go through (\(code.rawValue))."
        }
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
        // Match the server drop rate of 2 per second so NI callbacks do not spam.
        let now = Date()
        if let last = lastUWBRangeAt[id], now.timeIntervalSince(last) < 0.5 {
            return
        }
        lastUWBRangeAt[id] = now
        live?.sendUWBRange(peerID: id, distanceM: meters)
    }

    private func publishUWBTokenIfNeeded() {
        guard let live, match?.snapshot.tagMethod == "uwb" else { return }
        guard let token = ranger.localToken(), token != lastUWBToken else { return }
        live.sendUWBToken(token)
        lastUWBToken = token
    }

    private func stopUWB() {
        ranger.stop()
        uwbPeers = []
        uwbDistance = [:]
        lastUWBToken = nil
        lastUWBRangeAt = [:]
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
        case .coolingDown: return "Taunt is still cooling down."
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
            note = nil
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
            // A start event that landed before this rule existed should not
            // sit under the map once seekers are released.
            if note == "The hunt is on." {
                note = nil
            }
        case .lobby:
            break
        }
        if screen == .lobby, view.phase == .headStart || view.phase == .active || view.phase == .paused {
            enterLive()
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
        // FakeGameService UI tests must not touch CoreLocation; a started
        // CLBackgroundActivitySession crashes the simulator host on teardown.
        if live != nil {
            location.start()
        }
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
        if let refresh = auth.refreshToken {
            try? keychain.saveRefreshToken(refresh)
            live?.refreshToken = refresh
        }
        session = Session(displayName: auth.user.displayName, token: auth.accessToken)
        displayName = auth.user.displayName
        note = nil
        if let loaded = try? await service.arenas() { arenas = loaded }
        screen = .home
        await registerPendingDeviceTokenIfNeeded()
    }

    private func registerPendingDeviceTokenIfNeeded() async {
        guard session != nil, let token = pendingDeviceToken else { return }
        do {
            try await service.registerDeviceToken(token)
            pendingDeviceToken = nil
        } catch {
            // Keep the pending token; a later auth or retry can send it.
            note = "Could not register for push yet."
        }
    }

    func loadTimeline() async {
        guard let id = match?.snapshot.gameId else { return }
        if let events = try? await service.timeline(gameID: id) {
            timeline = TimelineOrder.sorted(events)
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
        } catch let error as ServiceError {
            lastError = error.code == .gameNotFound ? .notFound : .service(error.code)
            joinMessage = error.message
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
            note = Self.needBothRolesCopy
        } catch {
            lastError = .service(.internal)
            note = "Could not start the hunt."
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
        editor.load(
            name: arena.name,
            boundary: arena.boundary,
            zones: arena.zones,
            boundaryCircle: arena.boundaryCircle
        )
        tool = arena.boundaryCircle != nil ? .playCircle : .playArea
        editor.tool = editorTool(from: tool)
        refreshDraftsFromEditor()
    }

    private func refreshDraftsFromEditor() {
        draftBoundary = editor.boundary.vertices.map {
            VisualPoint(latitude: $0.latitude, longitude: $0.longitude)
        }
        draftBoundaryCircle = editor.boundaryCircle
        draftZones = editor.zones.map { $0.asVisual() }
        draftPending = editor.pendingVertices.map {
            VisualPoint(latitude: $0.latitude, longitude: $0.longitude)
        }
        draftCircleCenter = editor.pendingCircleCenterForMap.map {
            VisualPoint(latitude: $0.latitude, longitude: $0.longitude)
        }
        if let notice = editor.notice {
            note = notice
        }
    }

    private var userGeoPoint: GeoPoint? {
        guard let fix = location.lastFix else { return nil }
        return GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }

    private func issueCopy(_ issue: ArenaIssue) -> String {
        switch issue {
        case .playAreaTooSmall: return "Play area needs at least three points."
        case .playAreaRadiusInvalid: return "Play area radius must be between 30 m and 2,000 m."
        case let .selfIntersection(name): return "\(name) crosses itself."
        case let .outsidePlayArea(name): return "\(name) leaves the play area."
        }
    }

    private func editorTool(from tool: ArenaTool) -> EditorTool {
        switch tool {
        case .playArea: return .playArea
        case .playCircle: return .playCircle
        case .safe: return .safeCircle
        case .outOfBounds: return .outOfBounds
        case .spawn: return .seekerSpawn
        }
    }

    private func arenaTool(from tool: EditorTool) -> ArenaTool {
        switch tool {
        case .playArea: return .playArea
        case .playCircle: return .playCircle
        case .safeCircle: return .safe
        case .outOfBounds: return .outOfBounds
        case .seekerSpawn: return .spawn
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
