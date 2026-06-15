import SwiftUI

struct ResourceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(ResourceNavigationSection.allCases) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 4)

                        sectionItems(section)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .navigationTitle("Resources")
        .background(.bar)
    }

    private func sectionItems(_ section: ResourceNavigationSection) -> some View {
        ForEach(ResourceNavigationItem.items(in: section)) { item in
            Button {
                appModel.selectResource(item)
            } label: {
                ResourceNavigationRow(
                    item: item,
                    isSelected: appModel.selectedResource == item,
                    discoveredResource: item.discoveredResource(in: appModel.selectedDiscovery)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("resource.nav.\(item.id)")
        }
    }
}

private struct ResourceNavigationRow: View {
    var item: ResourceNavigationItem
    var isSelected: Bool
    var discoveredResource: KubernetesDiscoveredResource?

    var body: some View {
        HStack(spacing: 8) {
            Label(item.title, systemImage: item.systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

            Spacer(minLength: 6)

            if let discoveredResource {
                Image(systemName: discoveredResource.namespaced ? "folder" : "globe")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .help(discoveredResource.scopeTitle)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
    }
}
