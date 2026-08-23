import AVFoundation
import SwiftUI
import UIKit

struct QRScannerView: UIViewControllerRepresentable {
    let isTorchOn: Bool
    let onScan: (String) -> Bool
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let preview = CameraPreviewView()
        preview.previewLayer.session = context.coordinator.session
        preview.previewLayer.videoGravity = .resizeAspectFill
        controller.view = preview
        context.coordinator.start()
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.setTorch(isTorchOn)
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class CameraPreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let onScan: (String) -> Bool
        let onUnavailable: () -> Void
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "dev.xikxp1.budila.camera")
        private var camera: AVCaptureDevice?
        private var rejectedPayload: String?
        private(set) var completed = false

        init(onScan: @escaping (String) -> Bool, onUnavailable: @escaping () -> Void) {
            self.onScan = onScan
            self.onUnavailable = onUnavailable
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sessionFailed(_:)),
                name: AVCaptureSession.runtimeErrorNotification,
                object: session
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func start() {
            queue.async { [self] in
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    reportFailure()
                    return
                }
                let input: AVCaptureDeviceInput
                do {
                    input = try AVCaptureDeviceInput(device: camera)
                } catch {
                    reportFailure()
                    return
                }
                guard session.canAddInput(input) else {
                    reportFailure()
                    return
                }

                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    reportFailure()
                    return
                }

                session.beginConfiguration()
                session.addInput(input)
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                self.camera = camera
                session.startRunning()
            }
        }

        func handle(_ payload: String) {
            guard !completed, payload != rejectedPayload else { return }
            completed = onScan(payload)
            rejectedPayload = completed ? nil : payload
        }

        func resetRejectedPayload() {
            rejectedPayload = nil
        }

        func reportUnavailable() {
            completed = true
            onUnavailable()
        }

        func setTorch(_ isOn: Bool) {
            queue.async { [self] in
                setTorchNow(isOn)
            }
        }

        func stop() {
            queue.async { [self] in
                setTorchNow(false)
                session.stopRunning()
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            if metadataObjects.isEmpty {
                resetRejectedPayload()
                return
            }
            for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
                guard code.type == .qr, let payload = code.stringValue else { continue }
                handle(payload)
                return
            }
        }

        @objc private func sessionFailed(_ notification: Notification) {
            reportFailure()
        }

        private func reportFailure() {
            DispatchQueue.main.async { [weak self] in self?.reportUnavailable() }
        }

        private func setTorchNow(_ isOn: Bool) {
            guard let camera, camera.hasTorch else { return }
            let mode: AVCaptureDevice.TorchMode = isOn ? .on : .off
            guard camera.isTorchModeSupported(mode), (try? camera.lockForConfiguration()) != nil else { return }
            defer { camera.unlockForConfiguration() }
            camera.torchMode = mode
        }
    }
}

struct ScannerScreen: View {
    let purpose: ScannerPurpose
    let isAvailable: Bool
    @Binding var message: String?
    let onScan: (String) -> Bool
    let onEmergencyStop: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isTorchOn = false
    @State private var scannerFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if isAvailable && !scannerFailed {
                    ZStack(alignment: .bottom) {
                        QRScannerView(
                            isTorchOn: isTorchOn,
                            onScan: onScan,
                            onUnavailable: { scannerFailed = true }
                        )
                        .ignoresSafeArea()
                        VStack(spacing: 12) {
                            if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasTorch == true {
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
                            if isAvailable {
                                Button("Try Again") { scannerFailed = false }
                            }
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
        .alert("Budila", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var instruction: String {
        purpose == .enroll ? "Point the camera at the QR code you will keep away from bed." : "Find and scan your enrolled QR code."
    }
}
