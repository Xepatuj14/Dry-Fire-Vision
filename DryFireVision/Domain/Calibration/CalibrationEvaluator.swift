import Foundation

public struct CalibrationEvaluation: Equatable, Sendable {
    public let state: CalibrationReadinessState
    public let selectedPoseFrame: PoseFrame?

    public init(state: CalibrationReadinessState, selectedPoseFrame: PoseFrame?) {
        self.state = state
        self.selectedPoseFrame = selectedPoseFrame
    }
}

public struct CalibrationEvaluator: Sendable {
    private let configuration: CalibrationConfiguration
    private var stableFrames: [PoseFrame] = []
    private var stablePeriodStartTimestampSeconds: Double?

    public init(configuration: CalibrationConfiguration = CalibrationConfiguration()) {
        self.configuration = configuration
    }

    public mutating func evaluate(poseFrames: [PoseFrame]) -> CalibrationEvaluation {
        guard !poseFrames.isEmpty else {
            resetStability()
            return CalibrationEvaluation(state: .searchingForPerson, selectedPoseFrame: nil)
        }

        guard poseFrames.count == 1, let frame = poseFrames.first else {
            resetStability()
            return CalibrationEvaluation(state: .multiplePeople, selectedPoseFrame: nil)
        }

        if let adjustment = firstMissingRequiredJointAdjustment(in: frame) {
            resetStability()
            return CalibrationEvaluation(state: .adjust(adjustment), selectedPoseFrame: frame)
        }

        let requiredSamples = PoseJointID.fullBodyCalibrationRequired.compactMap { frame.sample(for: $0) }
        let averageConfidence = requiredSamples.map(\.confidence).reduce(0, +) / Double(requiredSamples.count)

        guard averageConfidence >= configuration.minimumAverageConfidence else {
            resetStability()
            return CalibrationEvaluation(state: .lowConfidence, selectedPoseFrame: frame)
        }

        guard let boundingBox = boundingBox(for: requiredSamples) else {
            resetStability()
            return CalibrationEvaluation(state: .adjust(.stepBack), selectedPoseFrame: frame)
        }

        if boundingBox.height < configuration.minimumBodyHeight {
            resetStability()
            return CalibrationEvaluation(state: .adjust(.moveCloser), selectedPoseFrame: frame)
        }

        if boundingBox.height > configuration.maximumBodyHeight || isNearVerticalEdge(boundingBox) {
            resetStability()
            return CalibrationEvaluation(state: .adjust(.stepBack), selectedPoseFrame: frame)
        }

        if boundingBox.minX < configuration.edgeMargin {
            resetStability()
            return CalibrationEvaluation(state: .adjust(.moveRight), selectedPoseFrame: frame)
        }

        if boundingBox.maxX > 1.0 - configuration.edgeMargin {
            resetStability()
            return CalibrationEvaluation(state: .adjust(.moveLeft), selectedPoseFrame: frame)
        }

        guard shoulderWidth(in: frame) != nil else {
            resetStability()
            return CalibrationEvaluation(state: .adjust(.keepShouldersVisible), selectedPoseFrame: frame)
        }

        if stablePeriodStartTimestampSeconds == nil {
            stablePeriodStartTimestampSeconds = frame.timestampSeconds
        }

        stableFrames.append(frame)
        trimStableFrames()

        guard let lastFrame = stableFrames.last else {
            return CalibrationEvaluation(state: .personDetected, selectedPoseFrame: frame)
        }

        let movement = maximumRequiredJointMovement(in: stableFrames)

        if movement > configuration.stabilityMovementThreshold {
            stableFrames = [frame]
            stablePeriodStartTimestampSeconds = frame.timestampSeconds
            return CalibrationEvaluation(state: .holdStill(progress: 0), selectedPoseFrame: frame)
        }

        let stableDuration = lastFrame.timestampSeconds - (stablePeriodStartTimestampSeconds ?? lastFrame.timestampSeconds)
        let progress = min(max(stableDuration / configuration.stabilityWindowSeconds, 0), 1)

        guard progress >= 1 else {
            return CalibrationEvaluation(state: .holdStill(progress: progress), selectedPoseFrame: frame)
        }

        guard stableFrames.count >= configuration.minimumBaselineSamples else {
            return CalibrationEvaluation(state: .capturingBaseline, selectedPoseFrame: frame)
        }

        guard let result = makeCalibrationResult(from: stableFrames, averageConfidence: averageConfidence) else {
            return CalibrationEvaluation(state: .adjust(.keepShouldersVisible), selectedPoseFrame: frame)
        }

        return CalibrationEvaluation(state: .ready(result), selectedPoseFrame: frame)
    }

    private func firstMissingRequiredJointAdjustment(in frame: PoseFrame) -> CalibrationAdjustmentReason? {
        for jointID in PoseJointID.fullBodyCalibrationRequired {
            guard let sample = frame.sample(for: jointID), sample.confidence >= configuration.minimumRequiredJointConfidence else {
                switch jointID {
                case .nose:
                    return .keepHeadVisible
                case .leftShoulder, .rightShoulder:
                    return .keepShouldersVisible
                case .leftWrist, .rightWrist, .leftElbow, .rightElbow:
                    return .keepWristsVisible
                case .leftHip, .rightHip:
                    return .keepHipsVisible
                case .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
                    return .keepLegsAndFeetVisible
                }
            }
        }

        return nil
    }

    private func boundingBox(for samples: [JointSample]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double, height: Double)? {
        guard let first = samples.first else {
            return nil
        }

        let bounds = samples.reduce((minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)) { partial, sample in
            (
                minX: min(partial.minX, sample.x),
                maxX: max(partial.maxX, sample.x),
                minY: min(partial.minY, sample.y),
                maxY: max(partial.maxY, sample.y)
            )
        }

        return (bounds.minX, bounds.maxX, bounds.minY, bounds.maxY, bounds.maxY - bounds.minY)
    }

    private func isNearVerticalEdge(_ boundingBox: (minX: Double, maxX: Double, minY: Double, maxY: Double, height: Double)) -> Bool {
        boundingBox.minY < configuration.edgeMargin || boundingBox.maxY > 1.0 - configuration.edgeMargin
    }

    private func shoulderWidth(in frame: PoseFrame) -> Double? {
        guard
            let left = frame.sample(for: .leftShoulder),
            let right = frame.sample(for: .rightShoulder),
            left.confidence >= configuration.minimumRequiredJointConfidence,
            right.confidence >= configuration.minimumRequiredJointConfidence
        else {
            return nil
        }

        let width = hypot(left.x - right.x, left.y - right.y)
        return width >= configuration.minimumShoulderWidth ? width : nil
    }

    private mutating func resetStability() {
        stableFrames.removeAll()
        stablePeriodStartTimestampSeconds = nil
    }

    private mutating func trimStableFrames() {
        guard let newestTimestamp = stableFrames.last?.timestampSeconds else {
            return
        }

        stableFrames.removeAll { newestTimestamp - $0.timestampSeconds > configuration.stabilityWindowSeconds }
    }

    private func maximumRequiredJointMovement(in frames: [PoseFrame]) -> Double {
        guard let first = frames.first, let last = frames.last else {
            return 0
        }

        return PoseJointID.fullBodyCalibrationRequired.compactMap { jointID -> Double? in
            guard let start = first.sample(for: jointID), let end = last.sample(for: jointID) else {
                return nil
            }

            return hypot(start.x - end.x, start.y - end.y)
        }.max() ?? 0
    }

    private func makeCalibrationResult(from frames: [PoseFrame], averageConfidence: Double) -> CalibrationResult? {
        guard frames.count >= configuration.minimumBaselineSamples else {
            return nil
        }

        var baselineJoints: [PoseJointID: JointSample] = [:]

        for jointID in PoseJointID.fullBodyCalibrationRequired {
            let samples = frames.compactMap { $0.sample(for: jointID) }
            guard samples.count >= configuration.minimumBaselineSamples else {
                return nil
            }

            baselineJoints[jointID] = JointSample(
                jointID: jointID,
                x: median(samples.map(\.x)),
                y: median(samples.map(\.y)),
                confidence: median(samples.map(\.confidence))
            )
        }

        let baselineFrame = PoseFrame(timestampSeconds: frames.last?.timestampSeconds ?? 0, joints: baselineJoints)
        guard let normalizationScale = shoulderWidth(in: baselineFrame) else {
            return nil
        }

        let duration = (frames.last?.timestampSeconds ?? 0) - (frames.first?.timestampSeconds ?? 0)
        let quality = CalibrationQuality(
            requiredJointCoverage: 1,
            averageConfidence: averageConfidence,
            confidenceStatus: confidenceStatus(for: averageConfidence)
        )

        return CalibrationResult(
            baselinePose: BaselinePose(joints: baselineJoints, durationSeconds: duration),
            normalizationScale: normalizationScale,
            normalizationScaleSource: .shoulderWidth,
            quality: quality
        )
    }

    private func confidenceStatus(for confidence: Double) -> ConfidenceStatus {
        if confidence >= configuration.highConfidenceThreshold {
            return .high
        }

        if confidence >= configuration.mediumConfidenceThreshold {
            return .medium
        }

        return .low
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }
}
