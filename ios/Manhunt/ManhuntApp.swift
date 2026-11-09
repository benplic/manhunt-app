import SwiftUI

@main
struct ManhuntApp: App {
    @State private var store = AppStore.makeForLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
