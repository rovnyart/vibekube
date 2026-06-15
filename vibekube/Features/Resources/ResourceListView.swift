import SwiftUI

struct ResourceListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sortOrder: [KeyPathComparator<KubernetesUnstructuredResource>] = [
        KeyPathComparator(\.displayName)
    ]

    let item: ResourceNavigationItem

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: appModel.resourceListTaskID(for: item)) {
            appModel.loadResourceList(for: item)
        }
        .accessibilityIdentifier("resource.list.\(item.id)")
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.resourceListState(for: item) {
        case .idle:
            EmptyStateView(
                title: idleTitle,
                subtitle: idleSubtitle,
                systemImage: item.systemImage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView("Loading \(item.title)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let snapshot):
            if filteredRows(snapshot).isEmpty {
                EmptyStateView(
                    title: "No \(item.title)",
                    subtitle: emptySubtitle(for: snapshot),
                    systemImage: item.systemImage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredRows(snapshot), sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.displayName)
                    TableColumn("Namespace", value: \.displayNamespace)
                    TableColumn("Kind", value: \.displayKind)
                    TableColumn("Status", value: \.displayStatus)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    TableColumn("Labels", value: \.labelsSummary)
                }
                .tableStyle(.inset)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                EmptyStateView(
                    title: "Could Not Load \(item.title)",
                    subtitle: message,
                    systemImage: "exclamationmark.triangle"
                )

                Button {
                    appModel.loadResourceList(for: item, force: true)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title2.weight(.semibold))

                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if let snapshot = loadedSnapshot {
                Text("\(snapshot.items.count) items")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                appModel.loadResourceList(for: item, force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(appModel.selectedConnectionState != .connected)
            .help("Refresh \(item.title)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var loadedSnapshot: ResourceListSnapshot? {
        if case .loaded(let snapshot) = appModel.resourceListState(for: item) {
            return snapshot
        }
        return nil
    }

    private var headerSubtitle: String {
        guard let resource = item.discoveredResource(in: appModel.selectedDiscovery) else {
            return appModel.selectedConnectionState == .connected ? "API resource not discovered" : "Disconnected"
        }

        let scope = resource.namespaced ? appModel.selectedNamespaceTitle : resource.scopeTitle
        return "\(resource.groupVersion) · \(resource.kind) · \(scope)"
    }

    private var idleTitle: String {
        appModel.selectedConnectionState == .connected ? "No Data Loaded" : "Disconnected"
    }

    private var idleSubtitle: String {
        if item.discoveredResource(in: appModel.selectedDiscovery) == nil {
            return "This API resource was not discovered on the selected cluster."
        }

        return appModel.selectedConnectionState == .connected ? "Refresh to load resources." : "Connect to a cluster first."
    }

    private func emptySubtitle(for snapshot: ResourceListSnapshot) -> String {
        let searchText = appModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            return "No rows match the current search."
        }

        if snapshot.query.resource.namespaced {
            return "Namespace: \(appModel.namespaceTitle(for: snapshot.query.namespaceSelection))"
        }

        return "Cluster-scoped resource"
    }

    private func filteredRows(_ snapshot: ResourceListSnapshot) -> [KubernetesUnstructuredResource] {
        let searchText = appModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = searchText.isEmpty
            ? snapshot.items
            : snapshot.items.filter { $0.searchBlob.contains(searchText) }

        return rows.sorted(using: sortOrder)
    }
}
