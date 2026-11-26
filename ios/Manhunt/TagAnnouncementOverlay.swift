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

/// Full-screen tag flash. The edge is a blurred stroke, so it fades into the map instead of
/// ending in a hard line, and the whole flash fades out. It stays mounted for that fade, so
/// the screen does not snap clear when the queue slot ends.
struct TagAnnouncementOverlay: View {
    var announcement: TagAnnouncement?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The flash on screen. Kept after `announcement` clears, so it can fade out.
    @State private var shown: TagAnnouncement?
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    /// Long enough for the fade to finish before the view is cleared.
    private static let fadeOutSeconds: Double = 0.5

    var body: some View {
        ZStack {
            if let shown {
                Rectangle()
                    .strokeBorder(HuntColor.danger, lineWidth: 40)
                    .blur(radius: 22)
                    .opacity(0.95)
                    .ignoresSafeArea()

                Text(shown.text)
                    .font(HuntFont.title(40))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(HuntColor.paper)
                    .shadow(color: .black.opacity(0.9), radius: 10)
                    .padding(32)
                    .scaleEffect(visible || reduceMotion ? 1 : 0.94)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: visible)
        .allowsHitTesting(false)
        .sensoryFeedback(.warning, trigger: announcement?.id)
        .onAppear { update(to: announcement) }
        .onChange(of: announcement) { _, new in update(to: new) }
    }

    @MainActor
    private func update(to new: TagAnnouncement?) {
        hideTask?.cancel()
        guard let new else {
            visible = false
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.fadeOutSeconds))
                guard !Task.isCancelled else { return }
                shown = nil
            }
            return
        }
        shown = new
        UIAccessibility.post(notification: .announcement, argument: new.text)
        visible = true
    }
}
