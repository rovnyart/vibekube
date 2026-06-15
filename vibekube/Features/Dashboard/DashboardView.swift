import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                connectionMessage

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    MetricTile(title: "API Groups", value: discoveryValue(\.apiGroupCount), systemImage: "square.stack.3d.up", tint: .indigo)
                    MetricTile(title: "API Resources", value: discoveryValue(\.resourceCount), systemImage: "shippingbox", tint: .blue)
                    MetricTile(title: "Namespaces", value: namespaceCount, systemImage: "folder", tint: .teal)
                    MetricTile(title: "Cluster Scoped", value: discoveryValue(\.clusterScopedResourceCount), systemImage: "globe", tint: .orange)
                }

                SectionSurface(title: "Cluster Snapshot", systemImage: "chart.bar.xaxis") {
                    DashboardRows(
                        cluster: appModel.selectedCluster,
                        discovery: appModel.selectedDiscovery,
                        selectedNamespace: appModel.selectedNamespaceTitle,
                        namespaceAccessError: appModel.namespaceAccessErrorMessage
                    )
                }

                SectionSurface(title: "Recent Events", systemImage: "waveform.path.ecg") {
                    EmptyStateView(
                        title: "No Events Loaded",
                        subtitle: "Disconnected",
                        systemImage: "waveform.path.ecg"
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("dashboard.view")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appModel.selectedCluster?.name ?? "No Cluster")
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)
                Text(appModel.selectedCluster?.contextName ?? "No context selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            StatusBadge(state: appModel.selectedConnectionState)
        }
    }

    private var namespaceCount: String {
        guard let discovery = appModel.selectedDiscovery else {
            return "-"
        }

        if discovery.namespaceDiscovery.errorMessage != nil {
            return "!"
        }

        return "\(discovery.namespaceDiscovery.items.count)"
    }

    private func discoveryValue(_ keyPath: KeyPath<KubernetesDiscoverySnapshot, Int>) -> String {
        guard let discovery = appModel.selectedDiscovery else {
            return "-"
        }

        return "\(discovery[keyPath: keyPath])"
    }

    @ViewBuilder
    private var connectionMessage: some View {
        if let message = appModel.connectionErrorMessage, !message.isEmpty {
            Label(message, systemImage: appModel.selectedConnectionState.systemImage)
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
                .accessibilityIdentifier("dashboard.connectionError")
        }
    }
}

private struct DashboardRows: View {
    let cluster: ClusterSummary?
    let discovery: KubernetesDiscoverySnapshot?
    let selectedNamespace: String
    let namespaceAccessError: String?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                Text("Context")
                    .foregroundStyle(.secondary)
                Text(cluster?.contextName ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Namespace")
                    .foregroundStyle(.secondary)
                Text(selectedNamespace)
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Source")
                    .foregroundStyle(.secondary)
                Text(cluster?.sourceName ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Auth")
                    .foregroundStyle(.secondary)
                Text(cluster?.authDescription ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Server")
                    .foregroundStyle(.secondary)
                Text(cluster?.server ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Version")
                    .foregroundStyle(.secondary)
                Text(cluster?.kubernetesVersion ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("API Groups")
                    .foregroundStyle(.secondary)
                Text(discovery.map { "\($0.apiGroupCount)" } ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("API Resources")
                    .foregroundStyle(.secondary)
                Text(discovery.map { "\($0.resourceCount)" } ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Namespace Access")
                    .foregroundStyle(.secondary)
                Text(namespaceAccessText)
                    .foregroundStyle(namespaceAccessError == nil ? Color.primary : Color.orange)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var namespaceAccessText: String {
        if let namespaceAccessError {
            return namespaceAccessError
        }

        return discovery == nil ? "Unknown" : "Loaded"
    }
}
