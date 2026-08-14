import Foundation

public struct PoseRecordingFixtureEnvelope: Codable, Equatable, Sendable {
    public let fixtureEncodingVersion: String
    public let recording: PoseRecording

    public init(
        fixtureEncodingVersion: String = VersionCatalog.current.poseEncodingVersion,
        recording: PoseRecording
    ) {
        self.fixtureEncodingVersion = fixtureEncodingVersion
        self.recording = recording
    }
}

public struct PoseRecordingFixtureCodec {
    private let supportedEncodingVersion: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(supportedEncodingVersion: String = VersionCatalog.current.poseEncodingVersion) {
        self.supportedEncodingVersion = supportedEncodingVersion
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    public func encode(_ recording: PoseRecording) throws -> Data {
        try encoder.encode(PoseRecordingFixtureEnvelope(recording: recording))
    }

    public func decode(_ data: Data) throws -> PoseRecording {
        let envelope = try decoder.decode(PoseRecordingFixtureEnvelope.self, from: data)
        guard envelope.fixtureEncodingVersion == supportedEncodingVersion else {
            throw PoseRecordingError.unsupportedFixtureEncoding(version: envelope.fixtureEncodingVersion)
        }

        return envelope.recording
    }
}
