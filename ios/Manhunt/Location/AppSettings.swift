import UIKit

/// Opens this app's page in Settings. The location banner uses it when
/// permission or precise accuracy is off. Manhunt never requests Always.
///
/// Also stores per-device ping alert preferences in UserDefaults. Sound and
/// torch-on-ping both default **off** so a quiet park night is not surprised
/// by a chime or flashlight flash until the player opts in.
enum AppSettings {
    static let pingSoundEnabledKey = "manhunt.pingSoundEnabled"
    static let pingFlashlightEnabledKey = "manhunt.pingFlashlightEnabled"

    @MainActor
    static var url: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    @MainActor
    static func open(_ application: UIApplication = .shared) {
        guard let url else { return }
        application.open(url)
    }

    static func pingSoundEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pingSoundEnabledKey)
    }

    static func setPingSoundEnabled(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: pingSoundEnabledKey)
    }

    static func pingFlashlightEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pingFlashlightEnabledKey)
    }

    static func setPingFlashlightEnabled(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: pingFlashlightEnabledKey)
    }
}
