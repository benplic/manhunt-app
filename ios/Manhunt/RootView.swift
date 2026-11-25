import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        return ZStack {
            Group {
                switch store.screen {
                case .signedOut:
                    SignInView()
                        // Play slides the landing up and away into Home.
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                case .home:
                    HomeView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12)),
                            removal: .opacity
                        ))
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
            if store.screen == .live || store.screen == .results {
                TagAnnouncementOverlay(announcement: store.tagAnnouncement)
            }
        }
        .environment(\.avatarStyles, store.avatarStyles)
        .animation(.snappy(duration: 0.35), value: store.screen)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            store.handleScenePhase(isBackground: phase == .background)
        }
        .alert("Play safely", isPresented: $store.showSafetyModal) {
            Button("Continue") { store.acknowledgeSafetyDisclaimer() }
        } message: {
            Text(AppStore.safetyDisclaimerCopy)
        }
    }
}
