import Foundation

#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
#endif

public final class AVFoundationCameraCaptureProvider: CameraCaptureProviding, @unchecked Sendable {
    #if canImport(AVFoundation)
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.dryfirevision.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputDelegate = CameraVideoOutputDelegate()
    private var currentInput: AVCaptureDeviceInput?
    private var configuredPosition: CameraPosition?
    private var isConfigured = false
    private var isPreviewRunning = false

    public init() {}

    public func authorizationStatus() async -> CameraAuthorizationStatus {
        mapAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    public func requestAuthorization() async -> CameraAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    public func startPreview(position: CameraPosition) async throws -> CameraPreviewSession {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureSessionIfNeeded(position: position)
                    self.configureVideoOutputMirroring()

                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                    }

                    self.isPreviewRunning = true
                    continuation.resume(returning: CameraPreviewSession(captureSession: self.captureSession, cameraPosition: position))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stopPreview() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }

                self.isPreviewRunning = false
                continuation.resume()
            }
        }
    }

    public func lifecycleEvents() -> AsyncStream<CameraCaptureLifecycleEvent> {
        AsyncStream { continuation in
            let notificationCenter = NotificationCenter.default
            let interrupted = notificationCenter.addObserver(
                forName: .AVCaptureSessionWasInterrupted,
                object: captureSession,
                queue: nil
            ) { _ in
                continuation.yield(.interrupted)
            }
            let interruptionEnded = notificationCenter.addObserver(
                forName: .AVCaptureSessionInterruptionEnded,
                object: captureSession,
                queue: nil
            ) { _ in
                continuation.yield(.interruptionEnded)
            }
            let runtimeError = notificationCenter.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: captureSession,
                queue: nil
            ) { _ in
                continuation.yield(.runtimeError)
            }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(interrupted)
                notificationCenter.removeObserver(interruptionEnded)
                notificationCenter.removeObserver(runtimeError)
            }
        }
    }

    public func frames() -> AsyncStream<CameraFrame> {
        videoOutputDelegate.frames()
    }

    private func configureSessionIfNeeded(position: CameraPosition) throws {
        guard !isConfigured || configuredPosition != position else {
            return
        }

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
        }

        captureSession.sessionPreset = .high

        if let currentInput {
            captureSession.removeInput(currentInput)
            self.currentInput = nil
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avCapturePosition) else {
            throw CameraCaptureError.deviceUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            throw CameraCaptureError.cannotAddInput
        }

        captureSession.addInput(input)
        currentInput = input

        if !captureSession.outputs.contains(where: { $0 === videoOutput }) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(videoOutputDelegate, queue: DispatchQueue(label: "com.dryfirevision.camera.videoOutput"))
            guard captureSession.canAddOutput(videoOutput) else {
                throw CameraCaptureError.cannotAddInput
            }

            captureSession.addOutput(videoOutput)
        }

        if let outputConnection = videoOutput.connection(with: .video),
           outputConnection.isVideoMirroringSupported {
            outputConnection.isVideoMirrored = false
        }

        configuredPosition = position
        isConfigured = true
    }

    private func configureVideoOutputMirroring() {
        guard let outputConnection = videoOutput.connection(with: .video),
              outputConnection.isVideoMirroringSupported else {
            return
        }

        outputConnection.isVideoMirrored = false
    }

    private func mapAuthorizationStatus(_ status: AVAuthorizationStatus) -> CameraAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
    #else
    public init() {}

    public func authorizationStatus() async -> CameraAuthorizationStatus {
        .restricted
    }

    public func requestAuthorization() async -> CameraAuthorizationStatus {
        .restricted
    }

    public func startPreview(position: CameraPosition) async throws -> CameraPreviewSession {
        throw CameraCaptureError.deviceUnavailable
    }

    public func stopPreview() async {}

    public func lifecycleEvents() -> AsyncStream<CameraCaptureLifecycleEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func frames() -> AsyncStream<CameraFrame> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    #endif
}

#if canImport(AVFoundation)
private extension CameraPosition {
    var avCapturePosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .rear:
            return .back
        }
    }
}

private final class CameraVideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var frameContinuation: AsyncStream<CameraFrame>.Continuation?

    func frames() -> AsyncStream<CameraFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            frameContinuation = continuation
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameContinuation?.yield(CameraFrame(sampleBuffer: sampleBuffer, timestampSeconds: timestampSeconds))
    }
}
#endif
