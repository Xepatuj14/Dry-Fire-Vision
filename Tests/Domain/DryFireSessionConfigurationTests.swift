import XCTest
@testable import DryFireVisionCore

final class DryFireSessionConfigurationTests: XCTestCase {
    func testDefaultsUseTenRepsAndFiveSecondRepWindow() {
        let configuration = DryFireSessionConfiguration()

        XCTAssertEqual(configuration.targetRepCount, 10)
        XCTAssertEqual(configuration.maximumRepDurationSeconds, 5)
        XCTAssertEqual(configuration.analysisConfiguration.plausibleRepDurationMaximumSeconds, 5)
        XCTAssertEqual(
            configuration.analysisConfiguration.version,
            "\(VersionCatalog.current.analysisConfigurationVersion)+repWindow5s"
        )
    }

    func testSessionLengthOptionsMapToTargetRepCount() {
        XCTAssertEqual(DryFireSessionConfiguration(sessionLength: .five).targetRepCount, 5)
        XCTAssertEqual(DryFireSessionConfiguration(sessionLength: .ten).targetRepCount, 10)
    }

    func testMaximumRepWindowOptionsMapToAnalysisConfiguration() {
        let expected: [(DryFireMaximumRepWindow, Double)] = [
            (.two, 2),
            (.three, 3),
            (.five, 5),
            (.ten, 10)
        ]

        for (window, seconds) in expected {
            let configuration = DryFireSessionConfiguration(maximumRepWindow: window)

            XCTAssertEqual(configuration.maximumRepDurationSeconds, seconds)
            XCTAssertEqual(configuration.analysisConfiguration.plausibleRepDurationMaximumSeconds, seconds)
        }
    }
}
