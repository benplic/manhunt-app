import SwiftUI

struct CreateGameView: View {
    @Environment(VisualStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "New game", subtitle: "Pick a park and a ruleset.", onBack: store.goHome)

                Text("ARENA")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(HuntColor.muted)
                ForEach(SamplePark.arenas) { arena in
                    Button {
                        store.arenaID = arena.id
                    } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(arena.name)
                                        .font(.headline)
                                        .foregroundStyle(HuntColor.paper)
                                    Text("\(arena.place) · \(arena.zones.count) zones")
                                        .font(.subheadline)
                                        .foregroundStyle(HuntColor.muted)
                                }
                                Spacer()
                                Image(systemName: store.arenaID == arena.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.arenaID == arena.id ? HuntColor.signal : HuntColor.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text("PRESET")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(HuntColor.muted)
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Classic Manhunt")
                            .font(.headline)
                            .foregroundStyle(HuntColor.paper)
                        Text("Head start, fuzzy reveals, hot / cold, safe zones, and the eight power-ups.")
                            .font(.subheadline)
                            .foregroundStyle(HuntColor.muted)
                        Button("Adjust rules", action: store.openPreset)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HuntColor.signal)
                    }
                }

                HuntButton(title: "Open lobby", systemImage: "person.3", action: store.openLobbyAsHost)
                    .accessibilityIdentifier("open-lobby")
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }
}
