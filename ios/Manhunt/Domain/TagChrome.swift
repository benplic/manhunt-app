import Foundation

/// Live seeker tagging chrome. QR stays available when method is uwb (spec §5.6).
enum TagChrome {
    static func showsQRScan(tagMethod: String?) -> Bool {
        // qr (default) and uwb both offer the scanner; uwb also shows peer Tag buttons.
        true
    }

    static func scanLabel(tagMethod: String?) -> String {
        tagMethod == "uwb" ? "Scan tag (fallback)" : "Scan tag"
    }
}
