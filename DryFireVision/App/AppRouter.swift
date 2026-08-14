import Foundation

public enum AppTab: Hashable, CaseIterable, Sendable {
    case train
    case progress
    case settings
}

public struct AppRouter: Sendable {
    public var selectedTab: AppTab

    public init(selectedTab: AppTab = .train) {
        self.selectedTab = selectedTab
    }
}
