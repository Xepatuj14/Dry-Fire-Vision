import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

public final class CameraPreviewSession: @unchecked Sendable {
    public let cameraPosition: CameraPosition

    #if canImport(AVFoundation)
    let captureSession: AVCaptureSession

    init(captureSession: AVCaptureSession, cameraPosition: CameraPosition) {
        self.captureSession = captureSession
        self.cameraPosition = cameraPosition
    }
    #endif

    public init(cameraPosition: CameraPosition = .front) {
        self.cameraPosition = cameraPosition

        #if canImport(AVFoundation)
        self.captureSession = AVCaptureSession()
        #endif
    }
}
