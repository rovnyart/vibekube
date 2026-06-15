import SwiftUI

struct ResourceListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sortOrder: [KeyPathComparator<KubernetesUnstructuredResource>] = [
        KeyPathComparator(\.displayName)
    ]
    @State private var selectedResourceID: KubernetesUnstructuredResource.ID?
    @State private var openDetailRows: [KubernetesUnstructuredResource] = []
    @State private var selectedDetailRowID: KubernetesUnstructuredResource.ID?

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
        let visibleRows = filteredRows(snapshot)
        let allRows = snapshot.items
        if openDetailRows.isEmpty {
            resourceListSurface(visibleRows: visibleRows, snapshot: snapshot)
                .onAppear {
                    reconcileDetailTabs(with: allRows)
                }
                .onChange(of: allRows.map(\.id)) {
                    reconcileDetailTabs(with: allRows)
                }
        } else {
            VSplitView {
                resourceListSurface(visibleRows: visibleRows, snapshot: snapshot)
                    .frame(minHeight: 220, idealHeight: 360, maxHeight: .infinity)

                ResourceDetailTabsView(
                    item: item,
                    rows: openDetailRows,
                    selectedRowID: selectedDetailRowID,
                    selectRow: selectDetailTab,
                    closeRow: closeDetailTab
                )
                .frame(minHeight: 260, idealHeight: 360, maxHeight: .infinity)
            }
            .onAppear {
                reconcileDetailTabs(with: allRows)
            }
            .onChange(of: allRows.map(\.id)) {
                reconcileDetailTabs(with: allRows)
            }
        }
    }

    @ViewBuilder
    private func resourceListSurface(
        visibleRows: [KubernetesUnstructuredResource],
        snapshot: ResourceListSnapshot
    ) -> some View {
        if visibleRows.isEmpty {
            EmptyStateView(
                title: "No \(item.title)",
                subtitle: emptySubtitle(for: snapshot),
                systemImage: item.systemImage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(visibleRows, selection: $selectedResourceID, sortOrder: $sortOrder) {
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
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: selectedResourceID) {
                openDetailTab(for: selectedResourceID, in: visibleRows)
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

    private func openDetailTab(
        for id: KubernetesUnstructuredResource.ID?,
        in rows: [KubernetesUnstructuredResource]
    ) {
        guard let id,
              let row = rows.first(where: { $0.id == id }) else {
            return
        }

        if let existingIndex = openDetailRows.firstIndex(where: { $0.id == row.id }) {
            openDetailRows[existingIndex] = row
        } else {
            openDetailRows.append(row)
        }

        selectedDetailRowID = row.id
    }

    private func selectDetailTab(_ id: KubernetesUnstructuredResource.ID) {
        selectedDetailRowID = id
        selectedResourceID = id
    }

    private func closeDetailTab(_ id: KubernetesUnstructuredResource.ID) {
        guard let closedIndex = openDetailRows.firstIndex(where: { $0.id == id }) else {
            return
        }

        openDetailRows.remove(at: closedIndex)
        if selectedDetailRowID == id {
            selectedDetailRowID = openDetailRows.indices.contains(closedIndex)
                ? openDetailRows[closedIndex].id
                : openDetailRows.last?.id
            selectedResourceID = selectedDetailRowID
        }
    }

    private func reconcileDetailTabs(with rows: [KubernetesUnstructuredResource]) {
        var rowByID: [KubernetesUnstructuredResource.ID: KubernetesUnstructuredResource] = [:]
        for row in rows {
            rowByID[row.id] = row
        }

        openDetailRows = openDetailRows.compactMap { rowByID[$0.id] }

        if let selectedDetailRowID,
           !openDetailRows.contains(where: { $0.id == selectedDetailRowID }) {
            self.selectedDetailRowID = openDetailRows.last?.id
            selectedResourceID = self.selectedDetailRowID
        } else if self.selectedDetailRowID == nil {
            self.selectedDetailRowID = openDetailRows.first?.id
            selectedResourceID = self.selectedDetailRowID
        }
    }
}

private struct ResourceDetailTabsView: View {
    let item: ResourceNavigationItem
    let rows: [KubernetesUnstructuredResource]
    let selectedRowID: KubernetesUnstructuredResource.ID?
    let selectRow: (KubernetesUnstructuredResource.ID) -> Void
    let closeRow: (KubernetesUnstructuredResource.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            if let selectedRow {
                ResourceDetailView(item: item, row: selectedRow)
                    .id(selectedRow.id)
            } else {
                EmptyStateView(
                    title: "Select a Resource",
                    subtitle: "Choose a tab to inspect its manifest.",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier("resource.detail.tabs.\(item.id)")
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rows) { row in
                        ResourceDetailTabButton(
                            row: row,
                            isSelected: row.id == selectedRowID,
                            select: {
                                selectRow(row.id)
                            },
                            close: {
                                closeRow(row.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }

            Divider()
                .frame(height: 20)

            Button {
                if let selectedRowID {
                    closeRow(selectedRowID)
                }
            } label: {
                Label("Close Tab", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(selectedRowID == nil)
            .help("Close Tab")
            .padding(.trailing, 10)
        }
        .background(.bar)
    }

    private var selectedRow: KubernetesUnstructuredResource? {
        guard let selectedRowID else {
            return rows.first
        }

        return rows.first { $0.id == selectedRowID } ?? rows.first
    }
}

private struct ResourceDetailTabButton: View {
    let row: KubernetesUnstructuredResource
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)

                    Text(row.displayName)
                        .lineLimit(1)

                    if row.displayNamespace != "-" {
                        Text(row.displayNamespace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.leading, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            Button(action: close) {
                Label("Close \(row.displayName)", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, 7)
        }
        .frame(maxWidth: 260)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.16))
        }
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
            ManifestYAMLView(yaml: snapshot.yaml)
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
