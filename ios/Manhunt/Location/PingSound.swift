import AudioToolbox
import Foundation

protocol PingSoundPlaying: AnyObject {
    func play()
}

/// Short system tick for a reveal ping. Kept behind an opt-in toggle.
final class SystemPingSound: PingSoundPlaying {
    /// Tink — short enough for a park ping without a long ringtone.
    private static let soundID: SystemSoundID = 1057

    func play() {
        AudioServicesPlaySystemSound(Self.soundID)
    }
}
