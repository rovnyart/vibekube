import SwiftUI

struct AIOverviewView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                SectionSurface(title: "Provider", systemImage: "network") {
                    VStack(alignment: .leading, spacing: 14) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
                            statusRow(title: "Status", value: appModel.aiIsConfigured ? "Ready" : "Incomplete", isHealthy: appModel.aiIsConfigured)
                            statusRow(title: "Shape", value: appModel.aiProviderSettings.shape.title)
                            statusRow(title: "Preset", value: appModel.aiProviderSettings.preset.title)
                            statusRow(title: "Base URL", value: appModel.aiProviderSettings.normalizedBaseURLString.isEmpty ? "Not set" : appModel.aiProviderSettings.normalizedBaseURLString)
                            statusRow(title: "API key", value: appModel.aiProviderSecrets.hasAPIKey ? "Stored in Keychain" : "Missing", isHealthy: appModel.aiProviderSecrets.hasAPIKey)
                            statusRow(title: "Model", value: appModel.aiProviderSettings.selectedModelID ?? "Not selected", isHealthy: appModel.aiProviderSettings.selectedModelID?.isEmpty == false)
                            statusRow(title: "Availability", value: availabilityTitle, isHealthy: availabilityIsHealthy)
                        }

                        HStack(spacing: 8) {
                            Button {
                                appModel.selectResource(.settings)
                            } label: {
                                Label("Open Settings", systemImage: "gearshape")
                            }

                            Button {
                                appModel.fetchAIModels()
                            } label: {
                                Label("Fetch Models", systemImage: "arrow.clockwise")
                            }
                            .disabled(!canFetchModels)

                            Button {
                                appModel.testAIProviderAvailability()
                            } label: {
                                Label("Test Provider", systemImage: "bolt.badge.checkmark")
                            }
                            .disabled(!canTestProvider)
                        }
                        .controlSize(.small)
                    }
                }

                SectionSurface(title: "Resource Assistant", systemImage: "sparkles") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: appModel.aiIsConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(appModel.aiIsConfigured ? .green : .orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appModel.aiIsConfigured ? "Available from resource details" : "Provider setup required")
                                    .font(.headline)

                                Text(resourceAssistantSubtitle)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let modelSummary {
                            Text(modelSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("ai.overview")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.largeTitle.weight(.semibold))
                Text("Provider status and resource-scoped assistance")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(appModel.aiIsConfigured ? "Ready" : "Incomplete", systemImage: appModel.aiIsConfigured ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appModel.aiIsConfigured ? .green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        }
    }

    private func statusRow(title: String, value: String, isHealthy: Bool? = nil) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let isHealthy {
                    Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isHealthy ? .green : .orange)
                }
                Text(value)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private var canFetchModels: Bool {
        appModel.aiProviderSettings.hasBaseURL &&
            appModel.aiProviderSecrets.hasAPIKey &&
            appModel.aiModelDiscoveryState != .loading
    }

    private var canTestProvider: Bool {
        appModel.aiProviderSettings.hasBaseURL &&
            appModel.aiProviderSecrets.hasAPIKey &&
            appModel.aiAvailabilityState != .checking
    }

    private var availabilityTitle: String {
        switch appModel.aiAvailabilityState {
        case .unknown:
            "Not tested"
        case .checking:
            "Checking"
        case .available(let message):
            message
        case .unavailable(let message):
            message
        }
    }

    private var availabilityIsHealthy: Bool? {
        switch appModel.aiAvailabilityState {
        case .available:
            true
        case .unavailable:
            false
        case .unknown, .checking:
            nil
        }
    }

    private var resourceAssistantSubtitle: String {
        if appModel.aiIsConfigured {
            return "Open any resource detail and use the sparkles action to ask about its redacted YAML, status, events, and selected logs."
        }
        return "Add a provider URL, Keychain-stored API key, and selected model before Vibekube can send AI requests."
    }

    private var modelSummary: String? {
        switch appModel.aiModelDiscoveryState {
        case .idle:
            nil
        case .loading:
            "Loading models..."
        case .loaded(let models):
            "\(models.count.formatted()) models loaded"
        case .failed(let message):
            message
        }
    }
}
