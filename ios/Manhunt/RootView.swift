import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.screen {
            case .signedOut:
                SignInView()
            case .home:
                HomeView()
            case .createGame:
                CreateGameView()
            case .lobby:
                LobbyView()
            case .live:
                LiveGameView()
            case .results:
                ResultsView()
            case .arenaEditor:
                ArenaEditorView()
            case .preset:
                PresetEditorView()
            }
        }
        .animation(.snappy(duration: 0.25), value: store.screen)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            store.handleScenePhase(isBackground: phase == .background)
        }
    }
}
