import XCTest
@testable import DryFireVisionCore

final class VersionCatalogTests: XCTestCase {
    func testCurrentVersionsMatchInitialPersistenceSpec() {
        let versions = VersionCatalog.current

        XCTAssertEqual(versions.persistenceSchemaVersion, 2)
        XCTAssertEqual(versions.analysisVersion, "1.0.0")
        XCTAssertEqual(versions.analysisConfigurationVersion, "1.1.0")
        XCTAssertEqual(versions.poseEncodingVersion, "1")
        XCTAssertEqual(versions.jointSetVersion, "vision-body-2d-v1")
        XCTAssertEqual(versions.coordinateConventionVersion, "dfv-normalized-2d-v1")
    }
}
