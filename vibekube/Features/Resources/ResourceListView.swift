import SwiftUI

struct ResourceListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sortOrder: [KeyPathComparator<KubernetesUnstructuredResource>] = [
        KeyPathComparator(\.displayName)
    ]
    @State private var selectedResourceID: KubernetesUnstructuredResource.ID?

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
            loadedContent(snapshot)
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

    @ViewBuilder
    private func loadedContent(_ snapshot: ResourceListSnapshot) -> some View {
        let rows = filteredRows(snapshot)
        if rows.isEmpty {
            EmptyStateView(
                title: "No \(item.title)",
                subtitle: emptySubtitle(for: snapshot),
                systemImage: item.systemImage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                Table(rows, selection: $selectedResourceID, sortOrder: $sortOrder) {
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
                .frame(minWidth: 420, idealWidth: 620, maxWidth: .infinity)

                if let selectedRow = selectedRow(in: rows) {
                    ResourceDetailView(item: item, row: selectedRow)
                        .frame(minWidth: 360, idealWidth: 460, maxWidth: 620)
                } else {
                    EmptyStateView(
                        title: "Select a Resource",
                        subtitle: "Choose a row to inspect its manifest.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .frame(minWidth: 360, idealWidth: 460, maxWidth: 620, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
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

    private func selectedRow(in rows: [KubernetesUnstructuredResource]) -> KubernetesUnstructuredResource? {
        guard let selectedResourceID else {
            return nil
        }

        return rows.first { $0.id == selectedResourceID }
    }
}

private struct ResourceDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    let item: ResourceNavigationItem
    let row: KubernetesUnstructuredResource

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: appModel.resourceDetailTaskID(for: item, row: row)) {
            appModel.loadResourceDetail(for: item, row: row)
        }
        .accessibilityIdentifier("resource.detail.\(item.id)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Text(detailSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                appModel.loadResourceDetail(for: item, row: row, force: true)
            } label: {
                Label("Refresh Manifest", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(appModel.selectedConnectionState != .connected)
            .help("Refresh Manifest")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.resourceDetailState(for: item, row: row) {
        case .idle:
            EmptyStateView(
                title: "No Manifest Loaded",
                subtitle: "Select a resource with a name and namespace.",
                systemImage: "doc.text"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView("Loading Manifest")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let snapshot):
            ScrollView {
                Text(snapshot.yaml)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .accessibilityIdentifier("resource.detail.yaml")
        case .failed(let message):
            VStack(spacing: 12) {
                EmptyStateView(
                    title: "Could Not Load Manifest",
                    subtitle: message,
                    systemImage: "exclamationmark.triangle"
                )

                Button {
                    appModel.loadResourceDetail(for: item, row: row, force: true)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailSubtitle: String {
        if row.displayNamespace == "-" {
            return row.displayKind
        }

        return "\(row.displayKind) · \(row.displayNamespace)"
    }
}
