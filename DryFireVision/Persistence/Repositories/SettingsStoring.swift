import Foundation

public protocol SettingsStoring: Sendable {
    var hasCompletedOnboarding: Bool { get async }
    var videoRetentionPreference: VideoRetentionPreference { get async }
    func setVideoRetentionPreference(_ preference: VideoRetentionPreference) async
}

public actor InMemorySettingsStore: SettingsStoring {
    public var hasCompletedOnboarding: Bool
    public var videoRetentionPreference: VideoRetentionPreference

    public init(
        hasCompletedOnboarding: Bool = false,
        videoRetentionPreference: VideoRetentionPreference = .keep
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.videoRetentionPreference = videoRetentionPreference
    }

    public func setVideoRetentionPreference(_ preference: VideoRetentionPreference) async {
        videoRetentionPreference = preference
    }
}

public actor UserDefaultsSettingsStore: SettingsStoring {
    private enum Keys {
        static let hasCompletedOnboarding = "dfv.hasCompletedOnboarding"
        static let videoRetentionPreference = "dfv.videoRetentionPreference"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var hasCompletedOnboarding: Bool {
        userDefaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    public var videoRetentionPreference: VideoRetentionPreference {
        guard let rawValue = userDefaults.string(forKey: Keys.videoRetentionPreference),
              let preference = VideoRetentionPreference(rawValue: rawValue) else {
            return .keep
        }
        return preference
    }

    public func setVideoRetentionPreference(_ preference: VideoRetentionPreference) async {
        userDefaults.set(preference.rawValue, forKey: Keys.videoRetentionPreference)
    }
}
