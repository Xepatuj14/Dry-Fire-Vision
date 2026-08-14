import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class SessionResultsViewModelTests: XCTestCase {
    func testFullAnalysisMapsToFullResultsState() async throws {
        let analysis = try await analyze(.good10)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.displayState, .full)
        XCTAssertEqual(state.repCountText, "10 valid reps analyzed")
        XCTAssertEqual(state.movementConsistencyText, "Available")
        XCTAssertEqual(state.representativeRep?.repNumberText, "Rep 1")
        XCTAssertEqual(state.fastestRep?.repNumberText, "Rep 1")
        XCTAssertTrue(state.outlierRows.isEmpty)
    }

    func testNoValidRepsMapsToDedicatedState() async throws {
        let analysis = try await analyze(.noValidReps)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.displayState, .noValidReps)
        XCTAssertEqual(state.averageDurationText, "Unavailable")
        XCTAssertEqual(state.movementConsistencyText, "Insufficient Data")
        XCTAssertNil(state.representativeRep)
        XCTAssertNil(state.fastestRep)
    }

    func testMissingConsistencyDoesNotFabricatePercentage() async throws {
        let analysis = try await analyze(.consistencyUnavailable)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.displayState, .degraded)
        XCTAssertEqual(state.movementConsistencyText, "Insufficient Data")
    }

    func testOutlierRowsMapFromDomainIDs() async throws {
        let analysis = try await analyze(.oneOutlier)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.outlierRows.map(\.repNumberText), ["Rep 10"])
        XCTAssertTrue(state.repRows[9].badges.contains("Outlier"))
    }

    func testSameRepCanBeFastestAndOutlier() async throws {
        let analysis = try await analyze(.fastestIsOutlier)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.fastestRep?.repNumberText, "Rep 10")
        XCTAssertTrue(state.repRows[9].badges.contains("Fastest"))
        XCTAssertTrue(state.repRows[9].badges.contains("Outlier"))
    }

    func testUnavailableMetricMapsToTextNotZero() async throws {
        let analysis = try await analyze(.degradedMetric)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.displayState, .degraded)
        XCTAssertTrue(state.repRows.contains { $0.headMetricText == "Unavailable" })
        XCTAssertFalse(state.repRows.contains { $0.headMetricText == "0" })
    }

    func testPartialTargetCountMapsActualAndTargetCounts() async throws {
        let analysis = try await analyze(.partial)
        let state = SessionResultsViewModel(analysis: analysis).state

        XCTAssertEqual(state.displayState, .degraded)
        XCTAssertEqual(state.repCountText, "7 valid reps analyzed")
        XCTAssertEqual(state.targetRepText, "Target: 10 reps")
    }

    private func analyze(_ fixtureID: SessionAnalysisFixtureID) async throws -> SessionAnalysis {
        try await SessionAnalysisPipeline().analyze(SessionAnalysisFixtureFactory.analysisInput(fixtureID))
    }
}
