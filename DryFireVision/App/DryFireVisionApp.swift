import SwiftUI

@main
struct DryFireVisionApp: App {
    private let dependencyContainer = DependencyContainer.production()

    var body: some Scene {
        WindowGroup {
            AppShellView(dependencyContainer: dependencyContainer)
        }
    }
}
