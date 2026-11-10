import SwiftUI

@main
struct ManhuntApp: App {
    @State private var store = AppStore.makeForLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in
                    store.open(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    store.open(url: url)
                }
        }
    }
}
