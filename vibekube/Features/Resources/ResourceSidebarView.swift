import SwiftUI

struct ResourceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: $appModel.selectedResource) {
            ForEach(ResourceNavigationSection.allCases) { section in
                Section(section.title) {
                    ForEach(ResourceNavigationItem.items(in: section)) { item in
                        ResourceNavigationRow(
                            item: item,
                            discoveredResource: item.discoveredResource(in: appModel.selectedDiscovery)
                        )
                            .tag(item as ResourceNavigationItem?)
                            .accessibilityIdentifier("resource.nav.\(item.id)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Resources")
        .background(.bar)
    }
}

private struct ResourceNavigationRow: View {
    var item: ResourceNavigationItem
    var discoveredResource: KubernetesDiscoveredResource?

    var body: some View {
        HStack(spacing: 8) {
            Label(item.title, systemImage: item.systemImage)

            Spacer(minLength: 6)

            if let discoveredResource {
                Image(systemName: discoveredResource.namespaced ? "folder" : "globe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(discoveredResource.scopeTitle)
            }
        }
    }
}
