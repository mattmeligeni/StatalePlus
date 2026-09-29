import SwiftUI
@preconcurrency import AVFoundation

/// Scanner QR nativo (AVFoundation). Chiama `onCode` una sola volta con il testo letto.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    var body: some View {
        NavigationStack {
            ZStack {
                if denied {
                    ContentUnavailableView("Fotocamera non disponibile", systemImage: "camera.fill",
                                           description: Text("Consenti l'accesso alla fotocamera da Impostazioni › Statale+."))
                } else {
                    QRCameraView { code in onCode(code); dismiss() }
                        .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 240, height: 240)
                }
            }
            .navigationTitle("Scansiona QR lezione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: break
                case .notDetermined: denied = !(await AVCaptureDevice.requestAccess(for: .video))
                default: denied = true
                }
            }
        }
    }
}

private struct QRCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let c = QRCameraController()
        c.onCode = onCode
        return c
    }
    func updateUIViewController(_ controller: QRCameraController, context: Context) {}
}

final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        nonisolated(unsafe) let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        nonisolated(unsafe) let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        MainActor.assumeIsolated {
            guard !done else { return }
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(value)
        }
    }
}
