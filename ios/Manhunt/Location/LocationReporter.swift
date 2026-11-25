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
    /// When the system last handed us any update, before the 3 m / 2.5 s throttle.
    private(set) var lastUpdateAt: Date?
    private var startedAt: Date?
    /// Silence this long while a hunt is open means the stream or the background session died.
    /// TODO: tune after the 10 minute lock-screen test (docs/testing/background-location-check.md).
    static let staleAfter: TimeInterval = 30

    var onUpdate: ((CLLocation) -> Void)?
    var onAccuracy: ((Accuracy) -> Void)?
    var onStreamFailure: (() -> Void)?
    /// Fires after the system permission sheet is answered, and on later status changes.
    var onAuthorizationChange: ((Accuracy) -> Void)?

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
        // Release the old session before taking a new one so a restart never stacks two.
        activity?.invalidate()
        activity = CLBackgroundActivitySession()
        startedAt = Date()
        // Staleness is measured from this start until the new stream delivers something.
        lastUpdateAt = nil
        stream?.cancel()
        stream = Task { [weak self] in
            do {
                let updates = CLLocationUpdate.liveUpdates()
                for try await update in updates {
                    // Any update proves the stream is alive, including a stationary one with
                    // no new location. A hider standing still must not look stale.
                    self?.lastUpdateAt = Date()
                    guard let self, let location = update.location else { continue }
                    self.consider(location)
                }
            } catch {
                await MainActor.run { self?.onStreamFailure?() }
            }
        }
        onAccuracy?(accuracy)
    }

    func stop() {
        stream?.cancel()
        stream = nil
        activity?.invalidate()
        activity = nil
        startedAt = nil
        lastSent = nil
    }

    /// Back in the foreground after a lock or background stay: if the stream went quiet,
    /// restart `liveUpdates()` and the background session. Never asks for Always.
    /// Returns true when it restarted.
    @discardableResult
    func restartIfStale(now: Date = Date()) -> Bool {
        guard stream != nil else { return false }
        guard LocationFreshness.isStale(
            lastUpdateAt: lastUpdateAt,
            startedAt: startedAt,
            now: now,
            staleAfter: Self.staleAfter
        ) else { return false }
        start()
        return true
    }

    /// One-shot fix for the arena editor. No background activity session.
    func requestFix() {
        requestWhenInUse()
        manager.requestLocation()
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
        let status = manager.authorizationStatus
        Task { @MainActor in
            let current = accuracy
            onAccuracy?(current)
            onAuthorizationChange?(current)
            // The first requestLocation is ignored while status is notDetermined.
            // Ask again once the person has answered the sheet.
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            lastFix = location
            lastUpdateAt = Date()
            onUpdate?(location)
            onAccuracy?(accuracy)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO: surface denied/unavailable location in the editor banner when product wants copy.
        _ = error
    }
}
