import SwiftUI
import UIKit

struct TagAnnouncement: Equatable, Identifiable {
    var id: Int
    var text: String

    init?(event: LiveEventDTO, blockList: PlayerBlockList) {
        guard let name = event.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        let shownName = event.playerId.map {
            blockList.displayName(for: $0.uuidString, fallback: name)
        } ?? name

        switch event.announcement {
        case "player_tagged":
            text = "\(shownName) was tagged!"
        case "player_tagged_out_of_bounds":
            text = "\(shownName) was tagged out of bounds!"
        default:
            return nil
        }
        id = event.seq
    }
}

struct TagAnnouncementOverlay: View {
    var announcement: TagAnnouncement?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAnimate = false

    var body: some View {
        ZStack {
            if let announcement {
                Rectangle()
                    .strokeBorder(HuntColor.danger, lineWidth: 28)
                    .shadow(color: HuntColor.danger, radius: 18)
                    .opacity(reduceMotion ? 0.85 : (didAnimate ? 0.45 : 1))

                Text(announcement.text)
                    .font(HuntFont.title(40))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(HuntColor.paper)
                    .shadow(color: .black.opacity(0.9), radius: 10)
                    .padding(32)
                    .scaleEffect(reduceMotion ? 1 : (didAnimate ? 1 : 0.9))
                    .opacity(reduceMotion ? 1 : (didAnimate ? 1 : 0.6))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .sensoryFeedback(.warning, trigger: announcement?.id)
        .onAppear { present(announcement) }
        .onChange(of: announcement?.id) { _, _ in
            present(announcement)
        }
    }

    private func present(_ announcement: TagAnnouncement?) {
        guard let announcement else { return }
        didAnimate = false
        UIAccessibility.post(notification: .announcement, argument: announcement.text)
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            didAnimate = true
        }
    }
}
