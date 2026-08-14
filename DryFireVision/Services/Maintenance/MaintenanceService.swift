import Foundation

public struct MaintenanceReport: Equatable, Sendable {
    public var mediaDeletionAttempts: Int
    public var strandedCapturingSessions: Int
    public var strandedProcessingSessions: Int
    public var orphanTemporaryFilesRemoved: Int

    public init(
        mediaDeletionAttempts: Int = 0,
        strandedCapturingSessions: Int = 0,
        strandedProcessingSessions: Int = 0,
        orphanTemporaryFilesRemoved: Int = 0
    ) {
        self.mediaDeletionAttempts = mediaDeletionAttempts
        self.strandedCapturingSessions = strandedCapturingSessions
        self.strandedProcessingSessions = strandedProcessingSessions
        self.orphanTemporaryFilesRemoved = orphanTemporaryFilesRemoved
    }
}

public protocol MaintenanceServicing: Sendable {
    func performMaintenance() async throws -> MaintenanceReport
}

public actor MaintenanceService: MaintenanceServicing {
    private let repository: SwiftDataSessionRepository
    private let maxDeletionsPerRun: Int

    public init(
        repository: SwiftDataSessionRepository,
        maxDeletionsPerRun: Int = 10
    ) {
        self.repository = repository
        self.maxDeletionsPerRun = maxDeletionsPerRun
    }

    public func performMaintenance() async throws -> MaintenanceReport {
        try await repository.performMaintenance(maxDeletions: maxDeletionsPerRun)
    }
}

public struct NoopMaintenanceService: MaintenanceServicing {
    public init() {}

    public func performMaintenance() async throws -> MaintenanceReport {
        MaintenanceReport()
    }
}
