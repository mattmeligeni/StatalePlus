import SwiftUI
@preconcurrency import AVFoundation

/// Scanner QR nativo (AVFoundation). Chiama `onCode` una sola volta con il testo letto.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false
    @State private var zoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                if denied {
                    ContentUnavailableView("Fotocamera non disponibile", systemImage: "camera.fill",
                                           description: Text("Consenti l'accesso alla fotocamera da Impostazioni › Statale+."))
                } else {
                    QRCameraView(zoom: zoom) { code in onCode(code); dismiss() }
                        .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 240, height: 240)
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: "minus.magnifyingglass")
                            Slider(value: $zoom, in: 1...QRCameraController.zoomMassimo)
                            Image(systemName: "plus.magnifyingglass")
                            Text("\(Double(zoom).formatted(.number.precision(.fractionLength(1)).locale(Formats.it)))×")
                                .font(.caption.monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(.horizontal, 24).padding(.bottom, 24)
                        .accessibilityLabel("Zoom")
                    }
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
    let zoom: CGFloat
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let c = QRCameraController()
        c.onCode = onCode
        return c
    }
    func updateUIViewController(_ controller: QRCameraController, context: Context) { controller.imposta(zoom: zoom) }
}

final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    /// Oltre questo valore l'immagine del QR diventa troppo sgranata per essere letta.
    static let zoomMassimo: CGFloat = 5
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        self.device = device
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

    /// Zoom digitale/ottico della fotocamera, limitato a quanto supporta il dispositivo.
    func imposta(zoom: CGFloat) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let massimo = min(Self.zoomMassimo, device.maxAvailableVideoZoomFactor)
        device.videoZoomFactor = min(max(zoom, device.minAvailableVideoZoomFactor), massimo)
        device.unlockForConfiguration()
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
