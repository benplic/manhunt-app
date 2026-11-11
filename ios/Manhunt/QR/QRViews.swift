import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import VisionKit

struct QRCodeView: View {
    var token: String

    var body: some View {
        if let image = QRCodeView.image(from: token) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("Could not draw the tag code.")
                .foregroundStyle(.secondary)
        }
    }

    static func image(from token: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(token.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Full-screen camera. Entering the code is the fallback when the camera cannot scan.
struct TagScanSheet: View {
    @Binding var code: String
    var onCode: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            QRScannerView(onCode: onCode)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
                    Text("The camera can't scan on this device. Enter the hider's tag code.")
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                TextField("Tag code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.black)
                Button("Enter code") {
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCode(trimmed)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.black)
            }
            .padding(16)
            .background(.black.opacity(0.72))
        }
        .background(.black)
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            try? scanner.startScanning()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            if case let .barcode(code) = item, let payload = code.payloadStringValue {
                onCode(payload)
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case let .barcode(code) = item, let payload = code.payloadStringValue {
                    onCode(payload)
                    return
                }
            }
        }
    }
}
