import DryFireVisionCore
import DryFireVisionTestFixtures
import XCTest

final class AudioEventDetectorTests: XCTestCase {
    private let detector = AudioEventDetector()

    func testNoImpulseProducesZeroCandidates() {
        let samples = LiveFireSyntheticFixtures.audio(eventTimes: [], amplitudes: [])

        XCTAssertTrue(detector.detectCandidates(in: samples).isEmpty)
    }

    func testOneCleanTransientProducesAcceptedCandidateAtTimestamp() {
        let events = detector.detectCandidates(in: LiveFireSyntheticFixtures.audio(eventTimes: [1.23], amplitudes: [0.95]))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].timestampSeconds, 1.23, accuracy: 0.000_001)
        XCTAssertEqual(events[0].status, .accepted)
        XCTAssertEqual(events[0].confidence, .high)
    }

    func testRingingInsideDebounceProducesOneCandidate() {
        let samples = LiveFireSyntheticFixtures.audio(eventTimes: [1.0, 1.03], amplitudes: [0.94, 0.90])

        let events = detector.detectCandidates(in: samples)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].timestampSeconds, 1.0, accuracy: 0.000_001)
    }

    func testSeparatedImpulsesProduceTwoCandidates() {
        let events = detector.detectCandidates(in: LiveFireSyntheticFixtures.audio(eventTimes: [1.0, 1.4], amplitudes: [0.95, 0.95]))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.status), [.accepted, .accepted])
    }

    func testClippedTransientIsAmbiguous() {
        let events = detector.detectCandidates(in: LiveFireSyntheticFixtures.input(.clippedAudio).audioSamples)

        XCTAssertEqual(events.first?.status, .ambiguous)
        XCTAssertEqual(events.first?.reason, .clippedAudio)
    }

    func testRepeatedAnalysisIsDeterministic() {
        let samples = LiveFireSyntheticFixtures.input(.mixedNoise).audioSamples

        XCTAssertEqual(detector.detectCandidates(in: samples), detector.detectCandidates(in: samples))
    }
}
