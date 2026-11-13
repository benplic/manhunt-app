import CoreGraphics

enum LiveHUDLayout {
    static let clockPointSize: CGFloat = 20
    static let barHeight: CGFloat = 3
    static let showsSecondColumn = false
}

enum PauseChrome {
    static func shouldToast(eventTitle: String) -> Bool {
        eventTitle != "paused"
    }
}
