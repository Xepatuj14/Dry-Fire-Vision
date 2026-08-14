import DryFireVisionTestFixtures
import XCTest
@testable import DryFireVisionCore

final class PoseRecordingFixtureCodecTests: XCTestCase {
    func testFixtureRoundTripPreservesRecording() throws {
        let codec = PoseRecordingFixtureCodec()
        let recording = SyntheticPoseFixtures.completedStableRecording()

        let data = try codec.encode(recording)
        let decoded = try codec.decode(data)

        XCTAssertEqual(decoded, recording)
    }

    func testUnsupportedFixtureEncodingFailsExplicitly() throws {
        let recording = SyntheticPoseFixtures.completedStableRecording()
        let envelope = PoseRecordingFixtureEnvelope(fixtureEncodingVersion: "unsupported", recording: recording)
        let data = try JSONEncoder().encode(envelope)
        let codec = PoseRecordingFixtureCodec()

        do {
            _ = try codec.decode(data)
            XCTFail("Expected unsupported fixture encoding error")
        } catch PoseRecordingError.unsupportedFixtureEncoding(let version) {
            XCTAssertEqual(version, "unsupported")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
