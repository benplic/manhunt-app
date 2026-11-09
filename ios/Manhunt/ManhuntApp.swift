import SwiftUI

@main
struct ManhuntApp: App {
    @State private var store = VisualStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
