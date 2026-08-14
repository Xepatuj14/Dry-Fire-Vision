import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

public final class CameraPreviewSession: @unchecked Sendable {
    #if canImport(AVFoundation)
    let captureSession: AVCaptureSession

    init(captureSession: AVCaptureSession) {
        self.captureSession = captureSession
    }
    #endif

    public init() {
        #if canImport(AVFoundation)
        self.captureSession = AVCaptureSession()
        #endif
    }
}
