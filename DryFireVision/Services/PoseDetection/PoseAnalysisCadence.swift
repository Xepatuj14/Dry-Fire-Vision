import Foundation

public struct PoseAnalysisCadence: Sendable {
    public let minimumIntervalSeconds: Double
    private var lastAnalyzedTimestampSeconds: Double?

    public init(minimumIntervalSeconds: Double = 0.1) {
        self.minimumIntervalSeconds = minimumIntervalSeconds
    }

    public mutating func shouldAnalyze(timestampSeconds: Double) -> Bool {
        guard let lastAnalyzedTimestampSeconds else {
            self.lastAnalyzedTimestampSeconds = timestampSeconds
            return true
        }

        guard timestampSeconds - lastAnalyzedTimestampSeconds >= minimumIntervalSeconds else {
            return false
        }

        self.lastAnalyzedTimestampSeconds = timestampSeconds
        return true
    }
}
