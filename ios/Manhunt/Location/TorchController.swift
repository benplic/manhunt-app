import AVFoundation
import Foundation

enum TorchError: Error, LocalizedError, Equatable {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Flashlight is not available on this device."
        case let .failed(message):
            "Could not toggle flashlight: \(message)"
        }
    }
}

protocol TorchControlling: AnyObject {
    var isAvailable: Bool { get }
    func setOn(_ on: Bool) throws
}

final class DeviceTorch: TorchControlling {
    var isAvailable: Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch && device.isTorchAvailable
    }

    func setOn(_ on: Bool) throws {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch,
              device.isTorchAvailable else {
            throw TorchError.unavailable
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw TorchError.failed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }
        if on {
            do {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } catch {
                throw TorchError.failed(error.localizedDescription)
            }
        } else {
            device.torchMode = .off
        }
    }
}
