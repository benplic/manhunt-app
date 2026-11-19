import Foundation

/// Live seeker tagging chrome. QR is the only tag path.
enum TagChrome {
    static func showsQRScan(tagMethod: String?) -> Bool { true }

    static func scanLabel(tagMethod: String?) -> String { "Scan tag" }
}