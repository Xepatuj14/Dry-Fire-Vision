import SwiftUI

public struct PrivacyRetentionView: View {
    private let settingsStore: any SettingsStoring
    @State private var preference: VideoRetentionPreference = .keep

    public init(settingsStore: any SettingsStoring) {
        self.settingsStore = settingsStore
    }

    public var body: some View {
        List {
            Section("Video Retention") {
                Picker("Video Retention", selection: $preference) {
                    ForEach(VideoRetentionPreference.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Video retention preference")
            }

            Section("Keep Video") {
                Text("Raw app-owned video remains available for later review when durable video recording is available.")
                    .accessibilityLabel("Keep Video. Raw app-owned video remains available for later review when durable video recording is available.")
            }

            Section("Analyze & Delete") {
                Text("Dry Fire Vision records temporarily, completes analysis, saves derived metrics and compact pose data, then deletes app-owned raw video.")
                Text("Derived metrics remain. Compact pose data may remain for Rep Review and Ghost Mode.")
                Text("Deletion starts only after successful analysis and persistence. The app does not claim deletion until removal is verified.")
            }
        }
        .navigationTitle("Privacy & Video Retention")
        .task {
            preference = await settingsStore.videoRetentionPreference
        }
        .onChange(of: preference) { _, newValue in
            Task {
                await settingsStore.setVideoRetentionPreference(newValue)
            }
        }
    }
}
