import AVFoundation
import SwiftUI
import VisionKit

struct QRScannerView: UIViewControllerRepresentable {
    let isTorchOn: Bool
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        Self.setTorch(isTorchOn)
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        setTorch(false)
        controller.stopScanning()
    }

    private static func setTorch(_ isOn: Bool) {
        guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = isOn ? .on : .off
        guard camera.isTorchModeSupported(mode), (try? camera.lockForConfiguration()) != nil else { return }
        defer { camera.unlockForConfiguration() }
        camera.torchMode = mode
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        var completed = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !completed else { return }
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue else { continue }
                completed = true
                onScan(payload)
                return
            }
        }
    }
}

struct ScannerScreen: View {
    let purpose: ScannerPurpose
    let isAvailable: Bool
    let onScan: (String) -> Void
    let onEmergencyStop: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isTorchOn = false

    var body: some View {
        NavigationStack {
            Group {
                if isAvailable {
                    ZStack(alignment: .bottom) {
                        QRScannerView(isTorchOn: isTorchOn, onScan: onScan).ignoresSafeArea()
                        VStack(spacing: 12) {
                            if AVCaptureDevice.default(for: .video)?.hasTorch == true {
                                Button {
                                    isTorchOn.toggle()
                                } label: {
                                    Label(
                                        isTorchOn ? "Turn Off Flashlight" : "Turn On Flashlight",
                                        systemImage: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isTorchOn ? .yellow : .gray)
                            }
                            Text(instruction)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(.black.opacity(0.75), in: .rect(cornerRadius: 14))
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "camera.fill",
                        description: Text("Allow camera access in Settings, then return to Budila.")
                    )
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 12) {
                            Button("Open Settings", action: onOpenSettings)
                                .buttonStyle(.borderedProminent)
                            if case .dismiss = purpose {
                                Button("Emergency Stop", role: .destructive, action: onEmergencyStop)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(purpose == .enroll ? "Enroll QR Code" : "Scan to Finish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if purpose == .enroll {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(purpose != .enroll)
    }

    private var instruction: String {
        purpose == .enroll ? "Point the camera at the QR code you will keep away from bed." : "Find and scan your enrolled QR code."
    }
}
