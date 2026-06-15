import SwiftUI

struct ResourceCatalogView: View {
    @EnvironmentObject private var appModel: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let discovery = appModel.selectedDiscovery, discovery.resourceCount > 0 {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        MetricTile(title: "API Groups", value: "\(discovery.apiGroupCount)", systemImage: "square.stack.3d.up", tint: .indigo)
                        MetricTile(title: "Resources", value: "\(discovery.resourceCount)", systemImage: "shippingbox", tint: .blue)
                        MetricTile(title: "Namespaced", value: "\(discovery.namespacedResourceCount)", systemImage: "folder", tint: .teal)
                        MetricTile(title: "Cluster Scoped", value: "\(discovery.clusterScopedResourceCount)", systemImage: "globe", tint: .purple)
                    }

                    ForEach(groupedResources(discovery), id: \.group) { group in
                        SectionSurface(title: group.group, systemImage: "square.grid.3x3") {
                            VStack(spacing: 0) {
                                ForEach(group.resources) { resource in
                                    ResourceCatalogRow(resource: resource)

                                    if resource.id != group.resources.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                        systemImage: "square.grid.3x3"
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("resource.catalog")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Resources")
                    .font(.largeTitle.weight(.semibold))
                Text(appModel.selectedCluster?.name ?? "No cluster")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            StatusBadge(state: appModel.selectedConnectionState)
        }
    }

    private var emptyTitle: String {
        appModel.selectedConnectionState == .connected ? "No API Resources" : "Disconnected"
    }

    private var emptySubtitle: String {
        appModel.selectedConnectionState == .connected ? "Discovery returned no listable resources." : "Connect to a cluster first."
    }

    private func groupedResources(_ discovery: KubernetesDiscoverySnapshot) -> [ResourceCatalogGroup] {
        Dictionary(grouping: discovery.discoveredResources, by: \.displayGroup)
            .map { group, resources in
                ResourceCatalogGroup(group: group, resources: resources.sorted())
            }
            .sorted { lhs, rhs in
                if lhs.group == rhs.group {
                    return false
                }
                if lhs.group == "core" {
                    return true
                }
                if rhs.group == "core" {
                    return false
                }
                return lhs.group.localizedStandardCompare(rhs.group) == .orderedAscending
            }
    }
}

private struct ResourceCatalogGroup {
    var group: String
    var resources: [KubernetesDiscoveredResource]
}

private struct ResourceCatalogRow: View {
    let resource: KubernetesDiscoveredResource

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(resource.kind)
                        .font(.body.weight(.medium))
                    Text(resource.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(resource.groupVersion)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Label(resource.scopeTitle, systemImage: resource.namespaced ? "folder" : "globe")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(resource.verbs.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 240, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 9)
        .accessibilityIdentifier("resource.catalog.row.\(resource.id)")
    }
}
