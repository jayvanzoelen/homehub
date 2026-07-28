import AVFoundation
import Combine
import CoreImage
import Foundation
import QuartzCore
import UIKit

final class MotionCameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var motionScore = 0.0

    private let sessionQueue = DispatchQueue(label: "homehub.guard-camera.session")
    private let outputQueue = DispatchQueue(label: "homehub.guard-camera.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var isConfigured = false
    private var videoOrientation: AVCaptureVideoOrientation = .portrait
    private var wantsToRun = false

    private var armed = false
    private var threshold = 28.0
    private var cooldown = 8.0
    private var previousFrame: [UInt8]?
    private var lastSampleTime = 0.0
    private var lastMotionTime = 0.0
    private var motionHandler: ((Data) -> Void)?

    private let sampleWidth = 160
    private let sampleHeight = 90

    func start() {
        DispatchQueue.main.async {
            self.permissionDenied = false
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

    func configureDetection(armed: Bool, threshold: Double, cooldown: Double) {
        outputQueue.async { [weak self] in
            guard let self else { return }
            if self.armed != armed {
                self.previousFrame = nil
            }
            self.armed = armed
            self.threshold = min(max(threshold, 0), 100)
            self.cooldown = max(cooldown, 1)
        }
    }

    func onMotion(_ handler: @escaping (Data) -> Void) {
        outputQueue.async { [weak self] in
            self?.motionHandler = handler
        }
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            self?.videoOrientation = orientation
            self?.applyOutputOrientation()
        }
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
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw MotionCameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .medium
        guard session.canAddInput(input), session.canAddOutput(videoOutput) else {
            throw MotionCameraError.configurationFailed
        }

        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        session.addOutput(videoOutput)
        isConfigured = true
        applyOutputOrientation()
    }

    private func applyOutputOrientation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func sampledFrame(from pixelBuffer: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        var frame = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 3)

        for y in 0 ..< sampleHeight {
            let sourceY = y * height / sampleHeight
            for x in 0 ..< sampleWidth {
                let sourceX = x * width / sampleWidth
                let sourceIndex = sourceY * bytesPerRow + sourceX * 4
                let targetIndex = (y * sampleWidth + x) * 3
                frame[targetIndex] = source[sourceIndex + 2]
                frame[targetIndex + 1] = source[sourceIndex + 1]
                frame[targetIndex + 2] = source[sourceIndex]
            }
        }
        return frame
    }

    private func score(current: [UInt8]) -> Double {
        guard let previousFrame, previousFrame.count == current.count else {
            self.previousFrame = current
            return 0
        }

        var changed = 0
        for index in stride(from: 0, to: current.count, by: 3) {
            let difference =
                abs(Int(current[index]) - Int(previousFrame[index]))
                + abs(Int(current[index + 1]) - Int(previousFrame[index + 1]))
                + abs(Int(current[index + 2]) - Int(previousFrame[index + 2]))
            if difference > 40 {
                changed += 1
            }
        }
        self.previousFrame = current
        return Double(changed) / Double(sampleWidth * sampleHeight) * 100
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
    }
}

extension MotionCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastSampleTime >= 0.25 else { return }
        lastSampleTime = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = sampledFrame(from: pixelBuffer)
        else {
            return
        }

        let currentScore = score(current: frame)
        DispatchQueue.main.async {
            self.motionScore = currentScore
        }

        guard armed,
              currentScore >= threshold,
              now - lastMotionTime >= cooldown,
              let jpeg = jpegData(from: pixelBuffer),
              let motionHandler
        else {
            return
        }
        lastMotionTime = now
        DispatchQueue.main.async {
            motionHandler(jpeg)
        }
    }
}

private enum MotionCameraError: LocalizedError {
    case unavailable
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The front camera is not available."
        case .configurationFailed:
            return "The motion camera could not be configured."
        }
    }
}
