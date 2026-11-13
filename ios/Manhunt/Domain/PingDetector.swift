import Foundation

/// A ping fires when the reveal countdown reaches zero. The server never shows a natural 0, it
/// resets to the interval on the same tick, so "countdown <= elapsed game seconds and it is now
/// above zero" means a pulse happened in between. The server `reveal` event is not used: it is
/// only sent when pins were added, which misses hot/cold pulses.
enum PingDetector {
    static func didPing(previous: PlayerViewDTO?, next: PlayerViewDTO) -> Bool {
        guard let previous,
              let before = previous.timers?.nextRevealInS,
              let after = next.timers?.nextRevealInS,
              next.phase == .headStart || next.phase == .active
        else { return false }
        let elapsed = next.gameElapsedS - previous.gameElapsedS
        return elapsed > 0 && before <= elapsed && after > 0
    }
}
