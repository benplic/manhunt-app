import Foundation
import Network

/// What the socket needs to know about the network: usable or not, and which radio.
struct NetworkPathState: Equatable, Sendable {
    var isSatisfied: Bool
    /// "wifi", "cellular", "wired", "other", or nil when unknown. A change means the old
    /// socket's route is gone even if the path stayed usable (Wi-Fi to cellular).
    var interface: String?
}

/// Seam over `NWPathMonitor` so tests can fake a Wi-Fi to cellular switch.
protocol NetworkPathObserving: AnyObject {
    var onChange: ((NetworkPathState) -> Void)? { get set }
    func start()
    func cancel()
}

final class SystemPathObserver: NetworkPathObserving, @unchecked Sendable {
    var onChange: ((NetworkPathState) -> Void)?
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "app.manhunt.network-path")

    func start() {
        // A cancelled NWPathMonitor cannot be restarted, so every start builds a new one.
        cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(Self.state(from: path))
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    func cancel() {
        monitor?.cancel()
        monitor = nil
    }

    private static func state(from path: NWPath) -> NetworkPathState {
        let interface: String?
        if path.usesInterfaceType(.wifi) {
            interface = "wifi"
        } else if path.usesInterfaceType(.cellular) {
            interface = "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = "wired"
        } else if path.status == .satisfied {
            interface = "other"
        } else {
            interface = nil
        }
        return NetworkPathState(isSatisfied: path.status == .satisfied, interface: interface)
    }
}
