import Foundation

public protocol CameraCaptureProviding: Sendable {
    func authorizationStatus() async -> CameraAuthorizationStatus
    func requestAuthorization() async -> CameraAuthorizationStatus
    func startPreview(position: CameraPosition) async throws -> CameraPreviewSession
    func stopPreview() async
    func lifecycleEvents() -> AsyncStream<CameraCaptureLifecycleEvent>
    func frames() -> AsyncStream<CameraFrame>
}
