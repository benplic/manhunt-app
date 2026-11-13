import SwiftUI

/// Bottom-left flashlight and bottom-right speaker/mic controls positioned above the live dock.
struct LiveControls: View {
    var flashlightOn: Bool
    var onToggleFlashlight: () -> Void
    var onTapSpeaker: () -> Void
    var onTapMic: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            Button(action: onToggleFlashlight) {
                Image(systemName: flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(
                        flashlightOn ? HuntColor.paper : Color.black.opacity(0.68),
                        in: Circle()
                    )
                    .overlay(
                        Circle().stroke(
                            flashlightOn ? HuntColor.signal : HuntColor.line,
                            lineWidth: flashlightOn ? 2 : 1
                        )
                    )
                    .foregroundStyle(flashlightOn ? HuntColor.ink : HuntColor.paper)
                    .shadow(
                        color: flashlightOn ? HuntColor.signal.opacity(0.55) : .clear,
                        radius: 10
                    )
            }
            .buttonStyle(.huntPress(.medium))
            .accessibilityLabel(flashlightOn ? "Turn flashlight off" : "Turn flashlight on")
            .accessibilityIdentifier("flashlight-button")

            Spacer()

            VStack(spacing: 10) {
                Button(action: onTapSpeaker) {
                    // TODO: wire voice radio playback toggle when audio transport ships.
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.68), in: Circle())
                        .overlay(Circle().stroke(HuntColor.line, lineWidth: 1))
                        .foregroundStyle(HuntColor.paper)
                }
                .buttonStyle(.huntPress(.light))
                .accessibilityLabel("Speaker")
                .accessibilityIdentifier("speaker-button")

                Button(action: onTapMic) {
                    // TODO: wire push-to-talk voice capture when audio transport ships.
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .background(Color.black.opacity(0.76), in: Circle())
                        .overlay(Circle().stroke(HuntColor.seeker.opacity(0.6), lineWidth: 1.5))
                        .foregroundStyle(HuntColor.seeker)
                }
                .buttonStyle(.huntPress(.light))
                .accessibilityLabel("Microphone")
                .accessibilityIdentifier("mic-button")
            }
        }
    }
}
