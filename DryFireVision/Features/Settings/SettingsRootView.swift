import SwiftUI

public struct SettingsRootView: View {
    private let featureFlags: FeatureFlags
    private let versions: VersionCatalog
    private let settingsStore: any SettingsStoring

    public init(
        featureFlags: FeatureFlags,
        versions: VersionCatalog,
        settingsStore: any SettingsStoring
    ) {
        self.featureFlags = featureFlags
        self.versions = versions
        self.settingsStore = settingsStore
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    NavigationLink("Privacy & Video Retention") {
                        PrivacyRetentionView(settingsStore: settingsStore)
                    }
                }

                if featureFlags.diagnosticsEnabled {
                    Section("Diagnostics") {
                        Text("Diagnostics")
                    }
                }

                Section("About") {
                    LabeledContent("Persistence Schema", value: "\(versions.persistenceSchemaVersion)")
                    LabeledContent("Analysis", value: versions.analysisVersion)
                    LabeledContent("Analysis Configuration", value: versions.analysisConfigurationVersion)
                    LabeledContent("Pose Encoding", value: versions.poseEncodingVersion)
                    LabeledContent("Joint Set", value: versions.jointSetVersion)
                    LabeledContent("Coordinate Convention", value: versions.coordinateConventionVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
