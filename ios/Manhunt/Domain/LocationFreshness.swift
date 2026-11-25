import Foundation

/// Decides whether the location stream has gone quiet. Pure, so tests never wait.
enum LocationFreshness {
    /// Stale when nothing arrived for `staleAfter`, measured from the last update, or from
    /// when the stream started if it never produced one.
    static func isStale(
        lastUpdateAt: Date?,
        startedAt: Date?,
        now: Date,
        staleAfter: TimeInterval
    ) -> Bool {
        guard let reference = lastUpdateAt ?? startedAt else { return false }
        return now.timeIntervalSince(reference) > staleAfter
    }
}
