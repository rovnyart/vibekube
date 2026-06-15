import SwiftUI

struct ClusterSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            if appModel.clusters.isEmpty {
                EmptyStateView(
                    title: appModel.kubeconfigState.title,
                    subtitle: appModel.kubeconfigState.detail,
                    systemImage: "externaldrive.badge.questionmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            } else {
                List(selection: $appModel.selectedClusterID) {
                    Section {
                        ForEach(appModel.clusters) { cluster in
                            ClusterRow(cluster: cluster)
                                .tag(cluster.id as String?)
                        }
                    } header: {
                        Text("Contexts")
                    } footer: {
                        Text(appModel.kubeconfigState.title)
                            .font(.caption)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.thinMaterial)
        .onChange(of: appModel.selectedClusterID) { _, selectedClusterID in
            appModel.selectCluster(id: selectedClusterID)
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "hexagon.fill")
                .font(.title2)
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vibekube")
                    .font(.headline)
                    .accessibilityIdentifier("app.title")
                Text("Kubernetes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ClusterRow: View {
    let cluster: ClusterSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.grid.cross")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cluster.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if cluster.isCurrentContext {
                        Text("Current")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.teal.opacity(0.12), in: Capsule())
                    }
                }

                Text(cluster.contextName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(cluster.namespace) · \(cluster.authDescription)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ConnectionDot(state: cluster.connectionState)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
