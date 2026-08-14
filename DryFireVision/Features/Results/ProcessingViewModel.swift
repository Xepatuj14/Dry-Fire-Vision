import Combine
import Foundation

public enum ProcessingStage: String, Equatable, Sendable {
    case preparing
    case analyzing
    case saving
    case complete
    case degraded
    case failed

    public var label: String {
        switch self {
        case .preparing:
            return "Preparing"
        case .analyzing:
            return "Analyzing movement"
        case .saving:
            return "Saving results"
        case .complete:
            return "Preparing results"
        case .degraded:
            return "Preparing partial results"
        case .failed:
            return "Analysis failed"
        }
    }
}

public enum ProcessingViewState: Equatable, Sendable {
    case preparing
    case analyzing
    case saving(SessionAnalysis)
    case complete(SessionAnalysis)
    case degraded(SessionAnalysis)
    case persistenceFailed(PersistenceFailureState)
    case failed(ProcessingFailureState)
}

public struct PersistenceFailureState: Equatable, Sendable {
    public let title: String
    public let message: String
    public let analysis: SessionAnalysis

    public init(title: String, message: String, analysis: SessionAnalysis) {
        self.title = title
        self.message = message
        self.analysis = analysis
    }
}

public struct ProcessingFailureState: Equatable, Sendable {
    public let title: String
    public let message: String
    public let reason: SessionAnalysisReason

    public init(title: String, message: String, reason: SessionAnalysisReason) {
        self.title = title
        self.message = message
        self.reason = reason
    }
}

@MainActor
public final class ProcessingViewModel: ObservableObject {
    @Published public private(set) var state: ProcessingViewState = .preparing
    @Published public private(set) var diagnostic: SessionWorkflowDiagnostic?

    private let sessionAnalyzer: any SessionAnalyzing
    private let sessionRepository: (any SessionRepository)?
    private let videoRetentionPreference: VideoRetentionPreference
    private let input: AnalysisInput
    private var analysisTask: Task<Void, Never>?

    public init(
        sessionAnalyzer: any SessionAnalyzing,
        sessionRepository: (any SessionRepository)? = nil,
        videoRetentionPreference: VideoRetentionPreference = .keep,
        input: AnalysisInput
    ) {
        self.sessionAnalyzer = sessionAnalyzer
        self.sessionRepository = sessionRepository
        self.videoRetentionPreference = videoRetentionPreference
        self.input = input
    }

    public func startAnalysisIfNeeded() {
        guard analysisTask == nil else {
            return
        }

        state = .analyzing
        analysisTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let analysis = try await sessionAnalyzer.analyze(input)
                guard let sessionRepository else {
                    await MainActor.run {
                        self.diagnostic = SessionWorkflowDiagnostic.make(
                            analysis: analysis,
                            persistedSessionID: nil
                        )
                        self.state = analysis.status == .completed ? .complete(analysis) : .degraded(analysis)
                    }
                    return
                }
                await MainActor.run {
                    self.state = .saving(analysis)
                }
                do {
                    let savedID = try await sessionRepository.save(
                        analysis,
                        videoRetentionPreference: videoRetentionPreference,
                        rawVideo: nil
                    )
                    let snapshot = try await sessionRepository.session(id: savedID)
                    guard let savedAnalysis = snapshot.analysis else {
                        await MainActor.run {
                            self.diagnostic = SessionWorkflowDiagnostic.make(
                                analysis: analysis,
                                persistedSessionID: nil,
                                failureCategory: .persistence
                            )
                            self.state = .persistenceFailed(Self.persistenceFailureState(for: analysis))
                        }
                        return
                    }
                    await MainActor.run {
                        self.diagnostic = SessionWorkflowDiagnostic.make(
                            analysis: savedAnalysis,
                            persistedSessionID: savedID
                        )
                        self.state = savedAnalysis.status == .completed ? .complete(savedAnalysis) : .degraded(savedAnalysis)
                    }
                } catch {
                    await MainActor.run {
                        self.diagnostic = SessionWorkflowDiagnostic.make(
                            analysis: analysis,
                            persistedSessionID: nil,
                            failureCategory: .persistence
                        )
                        self.state = .persistenceFailed(Self.persistenceFailureState(for: analysis))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.state = .failed(Self.failureState(for: SessionAnalysisReason.internalAnalysisFailure))
                }
            } catch let error as SessionAnalysisError {
                await MainActor.run {
                    self.diagnostic = nil
                    self.state = .failed(Self.failureState(for: error))
                }
            } catch {
                await MainActor.run {
                    self.diagnostic = nil
                    self.state = .failed(Self.failureState(for: SessionAnalysisReason.internalAnalysisFailure))
                }
            }
        }
    }

    public func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    public func retryPersistence() {
        guard case .persistenceFailed(let failure) = state,
              let sessionRepository else {
            return
        }

        state = .saving(failure.analysis)
        analysisTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let savedID = try await sessionRepository.save(
                    failure.analysis,
                    videoRetentionPreference: videoRetentionPreference,
                    rawVideo: nil
                )
                let snapshot = try await sessionRepository.session(id: savedID)
                guard let savedAnalysis = snapshot.analysis else {
                    await MainActor.run {
                        self.diagnostic = SessionWorkflowDiagnostic.make(
                            analysis: failure.analysis,
                            persistedSessionID: nil,
                            failureCategory: .persistence
                        )
                        self.state = .persistenceFailed(Self.persistenceFailureState(for: failure.analysis))
                    }
                    return
                }
                await MainActor.run {
                    self.diagnostic = SessionWorkflowDiagnostic.make(
                        analysis: savedAnalysis,
                        persistedSessionID: savedID
                    )
                    self.state = savedAnalysis.status == .completed ? .complete(savedAnalysis) : .degraded(savedAnalysis)
                }
            } catch {
                await MainActor.run {
                    self.diagnostic = SessionWorkflowDiagnostic.make(
                        analysis: failure.analysis,
                        persistedSessionID: nil,
                        failureCategory: .persistence
                    )
                    self.state = .persistenceFailed(Self.persistenceFailureState(for: failure.analysis))
                }
            }
        }
    }

    private static func failureState(for error: SessionAnalysisError) -> ProcessingFailureState {
        switch error {
        case .invalidRecording:
            return failureState(for: .invalidRecording)
        case .unusableCalibration:
            return failureState(for: .unusableCalibration)
        case .segmentationFailed:
            return failureState(for: .segmentationFailed)
        case .insufficientPoseData:
            return failureState(for: .insufficientPoseData)
        case .invalidAnalysisConfiguration:
            return failureState(for: .invalidAnalysisConfiguration)
        case .internalAnalysisFailure:
            return failureState(for: SessionAnalysisReason.internalAnalysisFailure)
        }
    }

    private static func failureState(for reason: SessionAnalysisReason) -> ProcessingFailureState {
        ProcessingFailureState(
            title: "Analysis Could Not Complete",
            message: message(for: reason),
            reason: reason
        )
    }

    private static func persistenceFailureState(for analysis: SessionAnalysis) -> PersistenceFailureState {
        PersistenceFailureState(
            title: "Results Not Saved",
            message: "Analysis completed, but Dry Fire Vision could not save this session. The in-memory results are still available for retry.",
            analysis: analysis
        )
    }

    private static func message(for reason: SessionAnalysisReason) -> String {
        switch reason {
        case .invalidRecording:
            return "The recording could not be analyzed."
        case .unusableCalibration:
            return "Calibration quality was not usable for analysis."
        case .segmentationFailed:
            return "Dry Fire Vision could not detect repetitions in this recording."
        case .insufficientPoseData:
            return "The recording did not contain enough pose samples."
        case .invalidAnalysisConfiguration:
            return "The analysis configuration is invalid."
        case .internalAnalysisFailure:
            return "Dry Fire Vision hit an internal analysis boundary."
        case .noValidReps:
            return "No valid repetitions were analyzed."
        case .comparisonUnavailable:
            return "Repetition comparison was unavailable, but individual reps may still be useful."
        case .metricUnavailable:
            return "Some movement metrics were unavailable."
        case .fewerThanTargetReps, .moreThanTargetReps, .degradedCalibration, .degradedSegmentation, .none:
            return "The session produced partial results."
        }
    }
}
