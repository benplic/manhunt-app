import Foundation
import NearbyInteraction

/// One discovered opponent. The token is an archived NIDiscoveryToken, opaque to us.
struct UWBPeer: Equatable, Identifiable {
    var id: UUID
    var name: String
    var token: String
}

protocol UWBRanging: AnyObject {
    var onDistance: ((UUID, Double) -> Void)? { get set }
    func setPeers(_ peers: [UWBPeer])
    func localToken() -> String?
    func stop()
}

enum UWBRangers {
    /// Precise distance is the U1/U2 capability. The simulator reports false.
    /// Uses NISession.deviceCapabilities (iOS 16+) instead of the deprecated isSupported.
    static var rangingAvailable: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    /// `enabled` is false for the fake service and for any device where UWB is missing.
    static func make(enabled: Bool) -> UWBRanging {
        if enabled, rangingAvailable {
            return NearbyUWBRanger()
        }
        return IdleUWBRanger()
    }
}

/// Simulator and pre-UWB phones. The hunt still runs on QR.
final class IdleUWBRanger: UWBRanging {
    var onDistance: ((UUID, Double) -> Void)?

    func setPeers(_ peers: [UWBPeer]) {}

    func localToken() -> String? { nil }

    func stop() {}
}

/// One NISession per peer, plus a dedicated discovery session that is never used
/// for peer config. Invalidating a peer session must not rotate the published token.
///
/// Apple does not publish the concurrent-session cap. WWDC20 shows one session per
/// peer and several at once. Exceeding the cap raises
/// NIError.Code.activeSessionsLimitExceeded and can invalidate every session.
/// TODO: measure the cap on two iPhone 11 or newer running the iOS version under test.
final class NearbyUWBRanger: NSObject, UWBRanging, NISessionDelegate {
    /// Peer sessions only. The discovery session is separate and not counted here.
    static let maxPeers = 5

    var onDistance: ((UUID, Double) -> Void)?

    private var sessions: [UUID: NISession] = [:]
    /// Publishes our discovery token. Never run a peer configuration on this session.
    private var discovery: NISession?
    private var hitLimit = false

    func localToken() -> String? {
        guard UWBRangers.rangingAvailable else { return nil }
        if discovery == nil {
            let session = NISession()
            session.delegate = self
            discovery = session
        }
        guard let token = discovery?.discoveryToken else { return nil }
        return Self.encode(token)
    }

    func setPeers(_ peers: [UWBPeer]) {
        let wanted = Array(peers.prefix(Self.maxPeers))
        let keep = Set(wanted.map(\.id))
        for (id, session) in sessions where !keep.contains(id) {
            session.invalidate()
            sessions.removeValue(forKey: id)
        }
        guard UWBRangers.rangingAvailable, !hitLimit else { return }
        for peer in wanted where sessions[peer.id] == nil {
            guard let token = Self.decode(peer.token) else { continue }
            let session = NISession()
            session.delegate = self
            sessions[peer.id] = session
            session.run(NINearbyPeerConfiguration(peerToken: token))
        }
    }

    func stop() {
        discovery?.invalidate()
        discovery = nil
        for session in sessions.values {
            session.invalidate()
        }
        sessions.removeAll()
        hitLimit = false
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let id = sessions.first(where: { $0.value === session })?.key,
              let distance = nearbyObjects.first?.distance
        else { return }
        onDistance?(id, Double(distance))
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        if session === discovery {
            discovery = nil
            return
        }
        if let ni = error as? NIError, ni.code == .activeSessionsLimitExceeded {
            // Opening another session would knock the rest down. Stop here.
            hitLimit = true
            for item in sessions.values {
                item.invalidate()
            }
            sessions.removeAll()
            return
        }
        sessions = sessions.filter { $0.value !== session }
    }

    private static func encode(_ token: NIDiscoveryToken) -> String? {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else { return nil }
        return data.base64EncodedString()
    }

    private static func decode(_ encoded: String) -> NIDiscoveryToken? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }
}
