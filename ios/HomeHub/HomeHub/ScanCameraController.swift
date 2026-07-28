import AVFoundation
import Combine
import Foundation
import UIKit

final class ScanCameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var capturedJPEG: Data?
    @Published private(set) var position: AVCaptureDevice.Position = .front

    private let sessionQueue = DispatchQueue(label: "homehub.scan-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var videoOrientation: AVCaptureVideoOrientation = .portrait
    private var activePosition: AVCaptureDevice.Position = .front
    private var wantsToRun = false
    private var captureInFlight = false

    var isFrontCamera: Bool {
        position == .front
    }

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        DispatchQueue.main.async {
            self.permissionDenied = false
            self.errorMessage = nil
        }
        sessionQueue.async {
            self.wantsToRun = true
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self else { return }
                if allowed {
                    self.configureAndStart()
                } else {
                    self.sessionQueue.async {
                        self.wantsToRun = false
                    }
                    DispatchQueue.main.async {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            sessionQueue.async {
                self.wantsToRun = false
            }
            DispatchQueue.main.async {
                self.permissionDenied = true
            }
        @unknown default:
            sessionQueue.async {
                self.wantsToRun = false
            }
            DispatchQueue.main.async {
                self.permissionDenied = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsToRun = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.captureInFlight else { return }
            self.captureInFlight = true
            DispatchQueue.main.async {
                self.isCapturing = true
            }
            self.applyOutputOrientation()
            let settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
            settings.photoQualityPrioritization = .balanced
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.captureInFlight else { return }
            let nextPosition: AVCaptureDevice.Position =
                self.activePosition == .front ? .back : .front
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: nextPosition
            ) else {
                self.publishError("The other camera is not available.")
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if let oldInput = self.videoInput {
                    self.session.removeInput(oldInput)
                }
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                    self.activePosition = nextPosition
                    self.applyOutputOrientation()
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.position = nextPosition
                    }
                } else {
                    if let oldInput = self.videoInput, self.session.canAddInput(oldInput) {
                        self.session.addInput(oldInput)
                    }
                    self.session.commitConfiguration()
                    self.publishError("The camera could not be switched.")
                }
            } catch {
                self.publishError("The camera could not be switched.")
            }
        }
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            self?.videoOrientation = orientation
            self?.applyOutputOrientation()
        }
    }

    func retake() {
        capturedImage = nil
        capturedJPEG = nil
        errorMessage = nil
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                do {
                    try self.configure()
                } catch {
                    self.publishError(error.localizedDescription)
                    return
                }
            }
            guard self.wantsToRun, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                self.errorMessage = nil
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw CameraError.unavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        videoInput = input
        activePosition = .front
        isConfigured = true
        applyOutputOrientation()
    }

    private func applyOutputOrientation() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = activePosition == .front
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isRunning = false
            self.errorMessage = "The camera was interrupted. Tap Retry when it is available."
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        configureAndStart()
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        DispatchQueue.main.async {
            self.isRunning = false
        }
        if error?.code == AVError.Code.mediaServicesWereReset.rawValue {
            configureAndStart()
        } else {
            publishError(error?.localizedDescription ?? "The camera stopped unexpectedly.")
        }
    }
}

extension ScanCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        sessionQueue.async {
            self.captureInFlight = false
        }
        DispatchQueue.main.async {
            self.isCapturing = false
        }
        if let error {
            publishError(error.localizedDescription)
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            publishError("The photo could not be captured.")
            return
        }
        DispatchQueue.main.async {
            self.capturedJPEG = data
            self.capturedImage = image
        }
    }
}

private enum CameraError: LocalizedError {
    case unavailable
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "No camera is available on this iPad."
        case .configurationFailed:
            return "The iPad camera could not be configured."
        }
    }
}
