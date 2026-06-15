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
                    MetricTile(title: "Nodes", value: "0", systemImage: "server.rack", tint: .indigo)
                    MetricTile(title: "Namespaces", value: "0", systemImage: "folder", tint: .teal)
                    MetricTile(title: "Pods", value: "0", systemImage: "shippingbox", tint: .blue)
                    MetricTile(title: "Warnings", value: "0", systemImage: "exclamationmark.triangle", tint: .orange)
                }

                SectionSurface(title: "Cluster Snapshot", systemImage: "chart.bar.xaxis") {
                    DashboardRows(cluster: appModel.selectedCluster)
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
                Text(cluster?.namespace ?? "None")
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
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
