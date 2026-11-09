import SwiftUI

struct ResultsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let result = store.match?.snapshot.result
        let winner = result?.winner ?? "none"
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(winnerTitle(winner))
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(HuntColor.signal)
                Text(store.arena.name)
                    .font(HuntFont.title(40))
                    .foregroundStyle(HuntColor.paper)
                Text(result?.reason ?? "The host ended the hunt.")
                    .foregroundStyle(HuntColor.muted)

                VStack(spacing: 8) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                        HStack {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 24, alignment: .leading)
                                .foregroundStyle(HuntColor.signal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .font(.body.weight(.semibold))
                                Text(player.role.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(HuntColor.muted)
                            }
                            Spacer()
                            Text("\(player.points)")
                                .font(.headline.monospacedDigit())
                        }
                        .foregroundStyle(HuntColor.paper)
                        .padding(12)
                        .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                HuntButton(title: "Back home", action: store.leaveResults)
                    .accessibilityIdentifier("back-home")
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }

    private var ranked: [VisualPlayer] {
        store.players.sorted { $0.points > $1.points }
    }

    private func winnerTitle(_ winner: String) -> String {
        switch winner {
        case "hiders": return "HIDERS WIN"
        case "seekers": return "SEEKERS WIN"
        default: return "HUNT OVER"
        }
    }
}
