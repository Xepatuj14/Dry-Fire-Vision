import Foundation

#if canImport(UIKit)
import UIKit
#endif

public protocol ApplicationSettingsOpening: Sendable {
    func openApplicationSettings() async
}

public struct SystemApplicationSettingsOpener: ApplicationSettingsOpening {
    public init() {}

    public func openApplicationSettings() async {
        #if canImport(UIKit)
        await MainActor.run {
            guard
                let settingsURL = URL(string: UIApplication.openSettingsURLString),
                UIApplication.shared.canOpenURL(settingsURL)
            else {
                return
            }

            UIApplication.shared.open(settingsURL)
        }
        #endif
    }
}
