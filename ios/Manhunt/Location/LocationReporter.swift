import CoreLocation
import Foundation
import UIKit

/// Precise location while a game is open. Never requests Always authorization.
@MainActor
final class LocationReporter: NSObject {
    enum Accuracy {
        case full
        case reduced
        case denied
        case notDetermined
    }

    private let manager = CLLocationManager()
    private var activity: CLBackgroundActivitySession?
    private var stream: Task<Void, Never>?
    private var lastSent: CLLocation?
    private var lastSentAt = Date.distantPast
    /// Last precise fix, used for a best-effort `final` ping.
    private(set) var lastFix: CLLocation?

    var onUpdate: ((CLLocation) -> Void)?
    var onAccuracy: ((Accuracy) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
    }

    var accuracy: Accuracy {
        switch manager.authorizationStatus {
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        default:
            return manager.accuracyAuthorization == .fullAccuracy ? .full : .reduced
        }
    }

    func requestWhenInUse() {
        // Spec: When In Use only. Never Always.
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        requestWhenInUse()
        UIDevice.current.isBatteryMonitoringEnabled = true
        activity = CLBackgroundActivitySession()
        stream?.cancel()
        stream = Task { [weak self] in
            do {
                let updates = CLLocationUpdate.liveUpdates()
                for try await update in updates {
                    guard let self, let location = update.location else { continue }
                    self.consider(location)
                }
            } catch {
                // TODO: surface location stream failures on the live reconnecting banner.
            }
        }
        onAccuracy?(accuracy)
    }

    func stop() {
        stream?.cancel()
        stream = nil
        activity = nil
        lastSent = nil
    }

    private func consider(_ location: CLLocation) {
        let moved = lastSent.map { location.distance(from: $0) >= 3 } ?? true
        let aged = Date().timeIntervalSince(lastSentAt) >= 2.5
        guard moved || aged else { return }
        lastSent = location
        lastFix = location
        lastSentAt = Date()
        onUpdate?(location)
    }
}

extension LocationReporter: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            onAccuracy?(accuracy)
        }
    }
}
