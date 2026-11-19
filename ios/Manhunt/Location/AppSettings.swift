import UIKit

/// Opens this app's page in Settings. The location banner uses it when
/// permission or precise accuracy is off. Manhunt never requests Always.
enum AppSettings {
    @MainActor
    static var url: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    @MainActor
    static func open() {
        guard let url else { return }
        // Read .shared inside the method. A default argument is nonisolated and
        // cannot touch the main-actor UIApplication.
        UIApplication.shared.open(url)
    }
}