import Foundation

public enum CalibrationAdjustmentReason: String, Codable, Equatable, Sendable {
    case stepBack
    case moveCloser
    case moveLeft
    case moveRight
    case keepHeadVisible
    case keepShouldersVisible
    case keepWristsVisible
    case keepHipsVisible
    case keepLegsAndFeetVisible
    case onlyOnePersonInFrame
    case holdStill
}

public enum CalibrationFailureReason: String, Codable, Equatable, Sendable {
    case poseDetectionFailed
    case invalidObservation
    case unsupportedPoseRequest
}

public enum CalibrationReadinessState: Equatable, Sendable {
    case startingCamera
    case searchingForPerson
    case personDetected
    case adjust(CalibrationAdjustmentReason)
    case multiplePeople
    case lowConfidence
    case holdStill(progress: Double)
    case capturingBaseline
    case ready(CalibrationResult)
    case failed(CalibrationFailureReason)
}
