import UIKit

/// Opens this app's page in Settings. The location banner uses it when
/// permission or precise accuracy is off. Manhunt never requests Always.
@MainActor
enum AppSettings {
    static var url: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    static func open(_ application: UIApplication = .shared) {
        guard let url else { return }
        application.open(url)
    }
}
