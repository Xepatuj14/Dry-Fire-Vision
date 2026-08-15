import Foundation

public enum CameraPosition: String, Codable, Equatable, Sendable {
    case front
    case rear

    public var toggled: CameraPosition {
        switch self {
        case .front:
            return .rear
        case .rear:
            return .front
        }
    }

    public var label: String {
        switch self {
        case .front:
            return "Front Camera"
        case .rear:
            return "Rear Camera"
        }
    }
}
