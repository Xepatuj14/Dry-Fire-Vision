import Foundation

#if canImport(CoreMedia)
import CoreMedia
#endif

public final class CameraFrame: @unchecked Sendable {
    public let timestampSeconds: Double

    #if canImport(CoreMedia)
    let sampleBuffer: CMSampleBuffer?

    init(sampleBuffer: CMSampleBuffer, timestampSeconds: Double) {
        self.sampleBuffer = sampleBuffer
        self.timestampSeconds = timestampSeconds
    }
    #endif

    public init(timestampSeconds: Double) {
        self.timestampSeconds = timestampSeconds
        #if canImport(CoreMedia)
        self.sampleBuffer = nil
        #endif
    }
}
