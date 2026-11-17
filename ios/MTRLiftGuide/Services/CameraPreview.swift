//
//  CameraPreview.swift
//  MTR Lift Guide
//
//  Live rear-camera feed used as the AR backdrop. Runs its own session
//  asynchronously so the UI never blocks on device startup.
//

import AVFoundation
import SwiftUI

final class CameraModel: NSObject, ObservableObject {
    enum Failure: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: return "Camera access was not granted."
            case .unavailable: return "No rear camera is available on this device."
            }
        }
    }

    @Published var isRunning = false
    @Published var failure: Failure?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "hk.isdn.mtrliftguide.camera")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.startSession() } else { self?.failure = .denied }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.failure = .denied }
        @unknown default:
            DispatchQueue.main.async { self.failure = .unavailable }
        }
    }

    private func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.failure = .unavailable }
                return
            }
            self.session.addInput(input)
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
}

struct CameraPreview: UIViewControllerRepresentable {
    @ObservedObject var model: CameraModel

    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController(model: model)
    }

    func updateUIViewController(_ controller: CameraViewController, context: Context) {
        controller.model = model
    }
}

final class CameraViewController: UIViewController {
    var model: CameraModel?
    private let previewLayer = AVCaptureVideoPreviewLayer()

    init(model: CameraModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        previewLayer.session = model?.session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        model?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model?.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}
