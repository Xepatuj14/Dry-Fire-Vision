import Foundation

public struct FeatureFlags: Equatable, Sendable {
    public var liveFireBetaEnabled: Bool
    public var diagnosticsEnabled: Bool
    public var experimentalMetricCardsEnabled: Bool

    public init(
        liveFireBetaEnabled: Bool,
        diagnosticsEnabled: Bool,
        experimentalMetricCardsEnabled: Bool
    ) {
        self.liveFireBetaEnabled = liveFireBetaEnabled
        self.diagnosticsEnabled = diagnosticsEnabled
        self.experimentalMetricCardsEnabled = experimentalMetricCardsEnabled
    }

    public static let production = FeatureFlags(
        liveFireBetaEnabled: false,
        diagnosticsEnabled: false,
        experimentalMetricCardsEnabled: false
    )
}
