import XCTest
@testable import DryFireVisionCore

final class FeatureFlagsTests: XCTestCase {
    func testProductionFeatureFlagsKeepLiveFireBetaDisabled() {
        let flags = FeatureFlags.production

        XCTAssertFalse(flags.liveFireBetaEnabled)
        XCTAssertFalse(flags.diagnosticsEnabled)
        XCTAssertFalse(flags.experimentalMetricCardsEnabled)
    }
}
