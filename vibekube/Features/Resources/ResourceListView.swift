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

private enum ResourceDetailPanelTab: String, CaseIterable, Identifiable {
    case overview
    case yaml
    case metadata
    case conditions

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .yaml:
            "YAML"
        case .metadata:
            "Metadata"
        case .conditions:
            "Conditions"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "list.bullet.rectangle"
        case .yaml:
            "doc.plaintext"
        case .metadata:
            "tag"
        case .conditions:
            "checklist"
        }
    }
}

private struct ResourceDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPanelTab: ResourceDetailPanelTab = .overview

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
        .onChange(of: row.id) {
            selectedPanelTab = .overview
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

            ResourceDetailPanelTabBar(
                selection: $selectedPanelTab,
                isEnabled: isLoaded
            )

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
            loadedContent(snapshot)
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

    @ViewBuilder
    private func loadedContent(_ snapshot: ResourceDetailSnapshot) -> some View {
        switch selectedPanelTab {
        case .overview:
            ResourceDetailOverviewView(
                row: row,
                summary: snapshot.summary,
                loadedAt: snapshot.loadedAt
            )
        case .yaml:
            ManifestYAMLView(yaml: snapshot.yaml)
        case .metadata:
            ResourceDetailMetadataView(summary: snapshot.summary)
        case .conditions:
            ResourceDetailConditionsView(conditions: snapshot.summary.conditions)
        }
    }

    private var isLoaded: Bool {
        if case .loaded = appModel.resourceDetailState(for: item, row: row) {
            return true
        }
        return false
    }

    private var detailSubtitle: String {
        if row.displayNamespace == "-" {
            return row.displayKind
        }

        return "\(row.displayKind) · \(row.displayNamespace)"
    }
}

private struct ResourceDetailPanelTabBar: View {
    @Binding var selection: ResourceDetailPanelTab
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResourceDetailPanelTab.allCases) { tab in
                ResourceDetailPanelTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    isEnabled: isEnabled
                ) {
                    selection = tab
                }
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16))
        }
        .accessibilityIdentifier("resource.detail.content.tabs")
    }
}

private struct ResourceDetailPanelTabButton: View {
    let tab: ResourceDetailPanelTab
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .imageScale(.small)
                Text(tab.title)
            }
            .font(.caption.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(minWidth: 82)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.26) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(tab.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("resource.detail.content.tab.\(tab.id)")
    }
}

private struct ResourceDetailOverviewView: View {
    let row: KubernetesUnstructuredResource
    let summary: KubernetesResourceDetailSummary
    let loadedAt: Date

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ResourceDetailFactTile(
                        title: "Status",
                        value: summary.status ?? row.displayStatus,
                        systemImage: "checkmark.circle",
                        tint: statusTint,
                        valueAccessibilityIdentifier: "resource.detail.overview.status"
                    )
                    ResourceDetailFactTile(
                        title: "Kind",
                        value: summary.kind ?? row.displayKind,
                        systemImage: "shippingbox",
                        tint: .blue
                    )
                    ResourceDetailFactTile(
                        title: "Namespace",
                        value: namespaceText,
                        systemImage: "square.stack.3d.up",
                        tint: .purple
                    )
                    ResourceDetailFactTile(
                        title: "Age",
                        value: row.ageDescription(),
                        systemImage: "clock",
                        tint: .orange
                    )
                    if let apiVersion = summary.apiVersion {
                        ResourceDetailFactTile(
                            title: "API Version",
                            value: apiVersion,
                            systemImage: "curlybraces",
                            tint: .cyan
                        )
                    }
                    ResourceDetailFactTile(
                        title: "Loaded",
                        value: loadedAt.formatted(date: .omitted, time: .standard),
                        systemImage: "arrow.clockwise",
                        tint: .secondary
                    )
                }

                if !summary.containers.isEmpty {
                    SectionSurface(title: "Containers", systemImage: "cube") {
                        VStack(spacing: 0) {
                            ForEach(summary.containers) { container in
                                ResourceContainerSummaryRow(container: container)
                            }
                        }
                    }
                }

                if !summary.ownerReferences.isEmpty {
                    SectionSurface(title: "Owners", systemImage: "point.3.connected.trianglepath.dotted") {
                        VStack(spacing: 0) {
                            ForEach(summary.ownerReferences) { owner in
                                ResourceOwnerSummaryRow(owner: owner)
                            }
                        }
                    }
                }

                if !summary.conditions.isEmpty {
                    SectionSurface(title: "Conditions", systemImage: "checklist") {
                        VStack(spacing: 10) {
                            ForEach(Array(summary.conditions.prefix(4))) { condition in
                                ResourceConditionSummaryRow(condition: condition)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier("resource.detail.overview")
    }

    private var namespaceText: String {
        if let namespace = summary.namespace, !namespace.isEmpty {
            return namespace
        }

        return row.displayNamespace == "-" ? "Cluster scoped" : row.displayNamespace
    }

    private var statusTint: Color {
        let status = (summary.status ?? row.displayStatus).lowercased()
        if status.contains("running") || status.contains("ready") || status == "true" {
            return .green
        }
        if status.contains("failed") || status.contains("error") || status.contains("false") {
            return .red
        }
        if status.contains("pending") || status.contains("progress") || status.contains("terminating") {
            return .orange
        }
        return .secondary
    }
}

private struct ResourceDetailMetadataView: View {
    let summary: KubernetesResourceDetailSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionSurface(title: "Identity", systemImage: "fingerprint") {
                    ResourceKeyValueList(rows: identityRows)
                }

                SectionSurface(title: "Labels", systemImage: "tag") {
                    ResourceKeyValueList(rows: sortedRows(summary.labels), emptyValue: "No labels")
                }

                SectionSurface(title: "Annotations", systemImage: "text.badge.checkmark") {
                    ResourceKeyValueList(rows: sortedRows(summary.annotations), emptyValue: "No annotations")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier("resource.detail.metadata")
    }

    private var identityRows: [(String, String)] {
        [
            ("Name", summary.name ?? "-"),
            ("Namespace", summary.namespace ?? "Cluster scoped"),
            ("UID", summary.uid ?? "-"),
            ("Resource Version", summary.resourceVersion ?? "-"),
            ("Created", summary.creationTimestamp ?? "-"),
            ("Deleting", summary.deletionTimestamp ?? "-")
        ]
    }

    private func sortedRows(_ values: [String: String]) -> [(String, String)] {
        values
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }
}

private struct ResourceDetailConditionsView: View {
    let conditions: [KubernetesConditionSummary]

    var body: some View {
        if conditions.isEmpty {
            EmptyStateView(
                title: "No Conditions",
                subtitle: "This resource does not report status conditions.",
                systemImage: "checklist"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(conditions) { condition in
                        ResourceConditionCard(condition: condition)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct ResourceDetailFactTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var valueAccessibilityIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                valueText

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minHeight: 96, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12))
        }
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(value.isEmpty ? "-" : value)
            .font(.headline)
            .lineLimit(1)
            .textSelection(.enabled)

        if let valueAccessibilityIdentifier {
            text.accessibilityIdentifier(valueAccessibilityIdentifier)
        } else {
            text
        }
    }
}

private struct ResourceKeyValueList: View {
    let rows: [(String, String)]
    var emptyValue = "No values"

    var body: some View {
        if rows.isEmpty {
            Text(emptyValue)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.0)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .leading)
                            .textSelection(.enabled)

                        Text(row.1.isEmpty ? "-" : row.1)
                            .font(.callout.monospaced())
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ResourceContainerSummaryRow: View {
    let container: KubernetesContainerSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: container.ready == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(container.ready == false ? .red : .green)

            VStack(alignment: .leading, spacing: 3) {
                Text(container.name)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)

                Text(container.image ?? "Image unavailable")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            if let restartCount = container.restartCount {
                Text("\(restartCount) restarts")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(restartCount > 0 ? .orange : .secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ResourceOwnerSummaryRow: View {
    let owner: KubernetesOwnerReferenceSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: owner.controller ? "link.circle.fill" : "link.circle")
                .foregroundStyle(owner.controller ? .blue : .secondary)

            Text(owner.kind)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(owner.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .textSelection(.enabled)

            Spacer()

            if owner.controller {
                Text("Controller")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ResourceConditionSummaryRow: View {
    let condition: KubernetesConditionSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ResourceConditionStatusPill(status: condition.status)

            VStack(alignment: .leading, spacing: 3) {
                Text(condition.type)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)

                if let reason = condition.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
    }
}

private struct ResourceConditionCard: View {
    let condition: KubernetesConditionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ResourceConditionStatusPill(status: condition.status)

                Text(condition.type)
                    .font(.headline)
                    .textSelection(.enabled)

                Spacer()

                if let lastTransitionTime = condition.lastTransitionTime {
                    Text(lastTransitionTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let reason = condition.reason, !reason.isEmpty {
                Text(reason)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
            }

            if let message = condition.message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ResourceConditionStatusPill: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch status.lowercased() {
        case "true":
            .green
        case "false":
            .red
        default:
            .orange
        }
    }
}
