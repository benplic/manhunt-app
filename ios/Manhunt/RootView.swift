import SwiftUI

struct RootView: View {
    @Environment(VisualStore.self) private var store

    var body: some View {
        Group {
            switch store.screen {
            case .signIn:
                SignInView()
            case .home:
                HomeView()
            case .create:
                CreateGameView()
            case .lobby:
                LobbyView()
            case .live:
                LiveGameView()
            case .results:
                ResultsView()
            case .arena:
                ArenaEditorView()
            case .preset:
                PresetEditorView()
            }
        }
        .animation(.snappy(duration: 0.25), value: store.screen)
        .preferredColorScheme(.dark)
    }
}
