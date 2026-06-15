import SwiftUI

struct ResourcePlaceholderView: View {
    @EnvironmentObject private var appModel: AppModel

    let item: ResourceNavigationItem

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: item.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let resource = item.discoveredResource(in: appModel.selectedDiscovery) {
                ResourceMetadataPanel(resource: resource)
                    .frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("resource.placeholder.\(item.id)")
    }

    private var subtitle: String {
        if item.discoveredResource(in: appModel.selectedDiscovery) != nil {
            return "API resource discovered"
        }

        if appModel.selectedConnectionState == .connected, item.requiresDiscoveredResource {
            return "This API resource was not discovered on the selected cluster."
        }

        return appModel.selectedConnectionState == .connected ? "No data loaded" : "Disconnected"
    }
}

private struct ResourceMetadataPanel: View {
    let resource: KubernetesDiscoveredResource

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                Text("Group")
                    .foregroundStyle(.secondary)
                Text(resource.displayGroup)
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Version")
                    .foregroundStyle(.secondary)
                Text(resource.version)
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Scope")
                    .foregroundStyle(.secondary)
                Text(resource.scopeTitle)
            }

            GridRow {
                Text("Verbs")
                    .foregroundStyle(.secondary)
                Text(resource.verbs.joined(separator: ", "))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
