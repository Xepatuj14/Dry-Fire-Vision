import Foundation

public enum DryFireSessionLength: Int, CaseIterable, Equatable, Sendable {
    case five = 5
    case ten = 10

    public var title: String {
        "\(rawValue) Reps"
    }
}

public enum DryFireMaximumRepWindow: Double, CaseIterable, Equatable, Sendable {
    case two = 2
    case three = 3
    case five = 5
    case ten = 10

    public var title: String {
        "\(Int(rawValue)) sec"
    }
}

public struct DryFireSessionConfiguration: Equatable, Sendable {
    public let sessionLength: DryFireSessionLength
    public let maximumRepWindow: DryFireMaximumRepWindow

    public init(
        sessionLength: DryFireSessionLength = .ten,
        maximumRepWindow: DryFireMaximumRepWindow = .five
    ) {
        self.sessionLength = sessionLength
        self.maximumRepWindow = maximumRepWindow
    }

    public var targetRepCount: Int {
        sessionLength.rawValue
    }

    public var maximumRepDurationSeconds: Double {
        maximumRepWindow.rawValue
    }

    public var analysisConfiguration: AnalysisConfiguration {
        AnalysisConfiguration.dryFireV1.replacing(
            version: "\(VersionCatalog.current.analysisConfigurationVersion)+repWindow\(Int(maximumRepDurationSeconds))s",
            plausibleRepDurationMaximumSeconds: maximumRepDurationSeconds
        )
    }
}
