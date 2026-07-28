import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let onOrientationChange: (AVCaptureVideoOrientation) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.mirrored = mirrored
        view.onOrientationChange = onOrientationChange
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        view.previewLayer.session = session
        view.mirrored = mirrored
        view.onOrientationChange = onOrientationChange
        view.updateOrientation()
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var mirrored = false
    var onOrientationChange: ((AVCaptureVideoOrientation) -> Void)?
    private var lastOrientation: AVCaptureVideoOrientation?

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let interfaceOrientation = window?.windowScene?.interfaceOrientation,
              let captureOrientation = interfaceOrientation.captureOrientation
        else {
            return
        }

        if let connection = previewLayer.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = captureOrientation
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }

        guard captureOrientation != lastOrientation else { return }
        lastOrientation = captureOrientation
        onOrientationChange?(captureOrientation)
    }
}

private extension UIInterfaceOrientation {
    var captureOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return nil
        }
    }
}
