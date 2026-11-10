import Foundation

/// Results lists the server event log in `seq` order. The client does not reorder
/// by type; a late tag must stay after an earlier reveal.
enum TimelineOrder {
    static func sorted(_ events: [TimelineEventDTO]) -> [TimelineEventDTO] {
        events.sorted { $0.seq < $1.seq }
    }
}
