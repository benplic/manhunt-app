import SwiftUI

/// Bottom-left flashlight and bottom-right speaker/mic controls positioned above the live dock.
/// A gear opens ping alert toggles (sound / torch flash), both default off.
struct LiveControls: View {
    var flashlightOn: Bool
    var pingSoundEnabled: Bool
    var pingFlashlightEnabled: Bool
    var onToggleFlashlight: () -> Void
    var onTogglePingSound: (Bool) -> Void
    var onTogglePingFlashlight: (Bool) -> Void
    var onTapSpeaker: () -> Void
    var onTapMic: () -> Void

    @State private var showPingSettings = false

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showPingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.68), in: Circle())
                        .overlay(Circle().stroke(HuntColor.line, lineWidth: 1))
                        .foregroundStyle(HuntColor.paper)
                }
                .buttonStyle(.huntPress(.light))
                .accessibilityLabel("Ping settings")
                .accessibilityIdentifier("ping-settings-button")

                Button(action: onToggleFlashlight) {
                    Image(systemName: flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
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
                        .animation(.snappy, value: flashlightOn)
                }
                .buttonStyle(.huntPress(.medium))
                .accessibilityLabel(flashlightOn ? "Turn flashlight off" : "Turn flashlight on")
                .accessibilityIdentifier("flashlight-button")
            }

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
        .sheet(isPresented: $showPingSettings) {
            PingAlertSettingsSheet(
                pingSoundEnabled: pingSoundEnabled,
                pingFlashlightEnabled: pingFlashlightEnabled,
                onTogglePingSound: onTogglePingSound,
                onTogglePingFlashlight: onTogglePingFlashlight
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
    }
}

struct PingAlertSettingsSheet: View {
    var pingSoundEnabled: Bool
    var pingFlashlightEnabled: Bool
    var onTogglePingSound: (Bool) -> Void
    var onTogglePingFlashlight: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Ping sound", isOn: Binding(
                        get: { pingSoundEnabled },
                        set: onTogglePingSound
                    ))
                    .accessibilityIdentifier("ping-sound-toggle")

                    Toggle("Ping flashlight", isOn: Binding(
                        get: { pingFlashlightEnabled },
                        set: onTogglePingFlashlight
                    ))
                    .accessibilityIdentifier("ping-flashlight-toggle")
                } footer: {
                    Text("Both stay off by default so a quiet park is not surprised. The flashlight button still works on its own.")
                }
            }
            .navigationTitle("Ping alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
