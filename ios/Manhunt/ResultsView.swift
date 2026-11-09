import SwiftUI

private struct ResultRow: Identifiable {
    var id: String
    var place: String
    var name: String
    var detail: String
    var points: Int
}

struct ResultsView: View {
    @Environment(VisualStore.self) private var store

    private let rows = [
        ResultRow(id: "jordan", place: "1", name: "Jordan Blake", detail: "Seeker · 2 tags", points: 110),
        ResultRow(id: "casey", place: "2", name: "Casey Lee", detail: "Seeker · 1 tag", points: 85),
        ResultRow(id: "quinn", place: "3", name: "Quinn Adler", detail: "Hider · still out", points: 70),
        ResultRow(id: "riley", place: "4", name: "Riley Chen", detail: "Hider · tagged", points: 40),
        ResultRow(id: "sam", place: "5", name: "Sam Patel", detail: "Hider · tagged", points: 25),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("SEEKERS WIN")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(HuntColor.signal)
                Text("Riverside Green")
                    .font(HuntFont.title(40))
                    .foregroundStyle(HuntColor.paper)
                Text("Called when the last hider was tagged. 28 minutes.")
                    .foregroundStyle(HuntColor.muted)

                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.place)
                                .font(.headline.monospacedDigit())
                                .frame(width: 24, alignment: .leading)
                                .foregroundStyle(HuntColor.signal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.body.weight(.semibold))
                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(HuntColor.muted)
                            }
                            Spacer()
                            Text("\(row.points)")
                                .font(.headline.monospacedDigit())
                        }
                        .foregroundStyle(HuntColor.paper)
                        .padding(12)
                        .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Text("WHAT HAPPENED")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(HuntColor.muted)
                VStack(alignment: .leading, spacing: 8) {
                    event("Head start ended. Seekers released.")
                    event("Quinn popped Ghost and skipped a reveal.")
                    event("Jordan tagged Riley at the south gate.")
                    event("Sam went dark. Last fix shown to both sides.")
                    event("Casey tagged Sam. Seekers win.")
                }
                .font(.subheadline)
                .foregroundStyle(HuntColor.paper)

                HuntButton(title: "Back home", action: store.goHome)
                    .accessibilityIdentifier("back-home")
                Text("Names and scores on this screen are sample copy so the layout is visible.")
                    .font(.footnote)
                    .foregroundStyle(HuntColor.muted)
            }
            .padding(20)
        }
        .background(HuntColor.ink)
    }

    private func event(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(HuntColor.signal).frame(width: 6, height: 6).padding(.top, 6)
            Text(text)
        }
    }
}
