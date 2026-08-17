import XCTest
@testable import DryFireVisionCore

final class DryFireSessionConfigurationTests: XCTestCase {
    func testDefaultsUseTenRepsAndFiveSecondRepWindow() {
        let configuration = DryFireSessionConfiguration()

        XCTAssertEqual(configuration.targetRepCount, 10)
        XCTAssertEqual(configuration.maximumRepDurationSeconds, 5)
        XCTAssertEqual(configuration.analysisConfiguration.primaryWristJointID, .rightWrist)
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
            let canonical = AnalysisConfiguration.dryFireV1.replacing(
                version: "\(VersionCatalog.current.analysisConfigurationVersion)+repWindow\(Int(seconds))s",
                plausibleRepDurationMaximumSeconds: seconds
            )

            XCTAssertEqual(configuration.analysisConfiguration, canonical)
            XCTAssertEqual(configuration.analysisConfiguration.primaryWristJointID, .rightWrist)
            XCTAssertEqual(configuration.maximumRepDurationSeconds, seconds)
            XCTAssertEqual(configuration.analysisConfiguration.plausibleRepDurationMaximumSeconds, seconds)
        }
    }

    func testSessionLengthDoesNotAffectAnalysisConfiguration() {
        let fiveRepConfiguration = DryFireSessionConfiguration(sessionLength: .five)
        let tenRepConfiguration = DryFireSessionConfiguration(sessionLength: .ten)

        XCTAssertEqual(fiveRepConfiguration.targetRepCount, 5)
        XCTAssertEqual(tenRepConfiguration.targetRepCount, 10)
        XCTAssertEqual(fiveRepConfiguration.analysisConfiguration, tenRepConfiguration.analysisConfiguration)
        XCTAssertEqual(fiveRepConfiguration.analysisConfiguration.primaryWristJointID, .rightWrist)
    }

    func testStandardDryFireComparisonJointsAreAvailable() {
        let normalizer = PhaseNormalizer(configuration: DryFireSessionConfiguration().analysisConfiguration)

        XCTAssertEqual(normalizer.comparisonJoints(), [
            .nose,
            .leftShoulder,
            .rightShoulder,
            .rightWrist
        ])
    }
}
