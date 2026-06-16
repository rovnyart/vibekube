import AppKit
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
        case .loading(let progress):
            ResourceListLoadingView(
                title: "Loading \(item.title)",
                progress: progress,
                cancel: {
                    appModel.cancelResourceList(for: item)
                }
            )
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

            if let watchStatus = visibleWatchStatus {
                ResourceWatchStatusBadge(status: watchStatus)
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

    private var visibleWatchStatus: ResourceWatchStatus? {
        guard loadedSnapshot != nil,
              let status = appModel.resourceWatchStatus(for: item),
              status != .idle else {
            return nil
        }

        return status
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

private struct ResourceWatchStatusBadge: View {
    let status: ResourceWatchStatus

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var title: String {
        switch status {
        case .idle:
            "Manual"
        case .starting:
            "Connecting"
        case .live:
            "Live"
        case .reconnecting:
            "Reconnecting"
        case .stale:
            "Stale"
        case .failed:
            "Watch failed"
        }
    }

    private var systemImage: String {
        switch status {
        case .idle:
            "pause.circle"
        case .starting:
            "dot.radiowaves.left.and.right"
        case .live:
            "dot.radiowaves.left.and.right"
        case .reconnecting:
            "arrow.triangle.2.circlepath"
        case .stale:
            "clock.badge.exclamationmark"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch status {
        case .idle:
            .secondary
        case .starting, .reconnecting:
            .orange
        case .live:
            .green
        case .stale:
            .secondary
        case .failed:
            .red
        }
    }

    private var helpText: String {
        switch status {
        case .idle:
            return "Live updates are not running."
        case .starting(let startedAt):
            return "Connecting live updates since \(startedAt.formatted(date: .omitted, time: .standard))."
        case .live(let since, let lastEventAt):
            if let lastEventAt {
                return "Live updates running since \(since.formatted(date: .omitted, time: .standard)); last event \(lastEventAt.formatted(date: .omitted, time: .standard))."
            }
            return "Live updates running since \(since.formatted(date: .omitted, time: .standard)); waiting for the first watch event."
        case .reconnecting(let state):
            let retry = state.nextRetryAt.formatted(date: .omitted, time: .standard)
            if let message = state.message, !message.isEmpty {
                return "Reconnecting watch, attempt \(state.attempt), next retry \(retry): \(message)"
            }
            return "Reconnecting watch, attempt \(state.attempt), next retry \(retry)."
        case .stale(let state):
            return "\(state.message) Last live attempt ended at \(state.endedAt.formatted(date: .omitted, time: .standard))."
        case .failed(let state):
            return "Watch failed at \(state.failedAt.formatted(date: .omitted, time: .standard)): \(state.message)"
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

private struct ResourceDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPanel: ResourceDetailPanel = .overview

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
            selectedPanel = .overview
        }
        .focusedSceneValue(\.resourceDetailCommandContext, detailCommandContext)
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
                selection: $selectedPanel,
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
        switch selectedPanel {
        case .overview:
            ResourceDetailOverviewView(
                row: row,
                summary: snapshot.summary,
                loadedAt: snapshot.loadedAt
            )
        case .events:
            ResourceDetailEventsView(detail: snapshot)
        case .logs:
            ResourceDetailLogsView(row: row, summary: snapshot.summary)
        case .environment:
            ResourceDetailEnvironmentView(summary: snapshot.summary)
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

    private var detailCommandContext: ResourceDetailCommandContext {
        ResourceDetailCommandContext(
            title: "\(row.displayKind)/\(row.displayName)",
            isLoaded: isLoaded,
            selectPanel: { panel in
                selectedPanel = panel
            },
            copyIdentity: {
                copyToPasteboard(resourceIdentityText)
            },
            copyYAML: {
                if case .loaded(let snapshot) = appModel.resourceDetailState(for: item, row: row) {
                    copyToPasteboard(snapshot.yaml)
                }
            }
        )
    }

    private var detailSubtitle: String {
        if row.displayNamespace == "-" {
            return row.displayKind
        }

        return "\(row.displayKind) · \(row.displayNamespace)"
    }

    private var resourceIdentityText: String {
        [
            "Kind: \(row.displayKind)",
            "Name: \(row.displayName)",
            "Namespace: \(row.displayNamespace == "-" ? "Cluster scoped" : row.displayNamespace)",
            "Resource: \(item.title)",
            "Cluster: \(appModel.selectedClusterID ?? "-")"
        ].joined(separator: "\n")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ResourceDetailPanelTabBar: View {
    @Binding var selection: ResourceDetailPanel
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResourceDetailPanel.allCases) { tab in
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
    let tab: ResourceDetailPanel
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .imageScale(.small)
                    .foregroundStyle(iconColor)
                Text(tab.title)
                    .foregroundStyle(titleColor)
            }
            .font(.caption.weight(isSelected ? .semibold : .medium))
            .frame(minWidth: 82)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tabBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(tab.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("resource.detail.content.tab.\(tab.id)")
    }

    private var titleColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.48)
        }

        return isSelected ? .primary : .primary.opacity(0.72)
    }

    private var iconColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.42)
        }

        return isSelected ? .primary.opacity(0.82) : .secondary.opacity(0.82)
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            Color(nsColor: .selectedContentBackgroundColor).opacity(0.26)
        } else if isEnabled {
            Color.primary.opacity(0.035)
        } else {
            Color.clear
        }
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

private struct ResourceDetailEventsView: View {
    @EnvironmentObject private var appModel: AppModel

    let detail: ResourceDetailSnapshot

    var body: some View {
        Group {
            switch appModel.resourceEventsState(for: detail) {
            case .idle:
                ProgressView("Loading Events")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            case .loading:
                ProgressView("Loading Events")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            case .loaded(let snapshot):
                loadedContent(snapshot)
            case .failed(let message):
                VStack(spacing: 12) {
                    EmptyStateView(
                        title: "Could Not Load Events",
                        subtitle: message,
                        systemImage: "exclamationmark.triangle"
                    )

                    Button {
                        appModel.loadResourceEvents(for: detail, force: true)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .task(id: appModel.resourceEventsTaskID(for: detail)) {
            appModel.loadResourceEvents(for: detail)
        }
        .accessibilityIdentifier("resource.detail.events")
    }

    @ViewBuilder
    private func loadedContent(_ snapshot: ResourceEventsSnapshot) -> some View {
        if snapshot.events.isEmpty {
            EmptyStateView(
                title: "No Events",
                subtitle: "Kubernetes has not reported events for this resource.",
                systemImage: "waveform.path.ecg"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(snapshot.events.count) events")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Loaded \(snapshot.loadedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Button {
                            appModel.loadResourceEvents(for: detail, force: true)
                        } label: {
                            Label("Refresh Events", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh Events")
                    }

                    VStack(spacing: 10) {
                        ForEach(snapshot.events) { event in
                            ResourceEventCard(event: event)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct ResourceDetailLogsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedContainerName = ""
    @State private var showsTimestamps = true
    @State private var showsPreviousLogs = false
    @State private var tailSelection: LogTailSelection = .last200
    @State private var followsLogs = false
    @State private var searchText = ""
    @State private var filtersMatches = false
    @State private var isExpanded = false
    @State private var isSavingLogs = false
    @State private var saveErrorMessage: String?

    let row: KubernetesUnstructuredResource
    let summary: KubernetesResourceDetailSummary

    var body: some View {
        Group {
            if isPod {
                podLogSurface
            } else {
                EmptyStateView(
                    title: "Logs Are Pod-Only",
                    subtitle: "Open a Pod row to load recent container logs.",
                    systemImage: "terminal"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .onAppear {
            reconcileContainer()
        }
        .onChange(of: containerNames) {
            reconcileContainer()
        }
        .onChange(of: showsPreviousLogs) {
            if showsPreviousLogs {
                followsLogs = false
            }
        }
        .onChange(of: followsLogs) {
            if followsLogs {
                showsPreviousLogs = false
            }
        }
        .onDisappear {
            if followsLogs {
                appModel.stopPodLogs()
            }
        }
        .sheet(isPresented: $isExpanded) {
            expandedLogSheet
        }
        .alert(
            "Could Not Save Logs",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .accessibilityIdentifier("resource.detail.logs")
    }

    @ViewBuilder
    private var podLogSurface: some View {
        let containerName = selectedContainerForRequest
        let state = currentLogState

        VStack(spacing: 0) {
            header

            Divider()

            logContent(state)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: currentTaskID) {
            appModel.loadPodLogs(
                for: row,
                containerName: containerName,
                timestamps: showsTimestamps,
                previous: showsPreviousLogs,
                tailLines: tailSelection.lineCount,
                follow: followsLogs
            )
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(followsLogs ? "Live Logs" : "Recent Logs")
                        .font(.headline)

                    Text(logSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer()

                if containerNames.count > 1 {
                    Picker("Container", selection: $selectedContainerName) {
                        ForEach(containerNames, id: \.self) { containerName in
                            Text(containerName).tag(containerName)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                Button {
                    isExpanded = true
                } label: {
                    Label("Expand Logs", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Expand Logs")

                Button {
                    refreshLogs()
                } label: {
                    Label("Refresh Logs", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(appModel.selectedConnectionState != .connected)
                .help("Refresh Logs")
            }

            HStack(spacing: 12) {
                Toggle("Timestamps", isOn: $showsTimestamps)
                    .toggleStyle(.checkbox)

                Toggle("Previous", isOn: $showsPreviousLogs)
                    .toggleStyle(.checkbox)
                    .help("Show logs from the previously terminated container instance")

                Toggle("Live", isOn: $followsLogs)
                    .toggleStyle(.checkbox)
                    .disabled(showsPreviousLogs)

                Picker("Tail", selection: $tailSelection) {
                    ForEach(LogTailSelection.allCases) { selection in
                        Text(selection.title).tag(selection)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                .disabled(followsLogs)

                Divider()
                    .frame(height: 18)

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search logs", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)

                Toggle("Grep", isOn: $filtersMatches)
                    .toggleStyle(.checkbox)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button {
                    saveDisplayedLogs()
                } label: {
                    Label("Save Displayed", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(isSavingLogs || displayedLogTextForCurrentState.isEmpty)

                Button {
                    Task {
                        await downloadAllLogs()
                    }
                } label: {
                    Label("Download All", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .disabled(isSavingLogs || appModel.selectedConnectionState != .connected)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func logContent(_ state: PodLogLoadState) -> some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading Logs")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        case .failed(let message):
            VStack(spacing: 12) {
                EmptyStateView(
                    title: "Could Not Load Logs",
                    subtitle: message,
                    systemImage: "exclamationmark.triangle"
                )

                Button {
                    appModel.loadPodLogs(
                        for: row,
                        containerName: selectedContainerForRequest,
                        timestamps: showsTimestamps,
                        previous: showsPreviousLogs,
                        tailLines: tailSelection.lineCount,
                        follow: followsLogs,
                        force: true
                    )
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        case .loaded(let snapshot):
            VStack(spacing: 0) {
                HStack {
                    Text(statusText(for: snapshot))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(displayedLogText(snapshot.text), forType: .string)
                    } label: {
                        Label("Copy Displayed Logs", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Displayed Logs")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))

                Divider()

                LogTextSurface(
                    text: snapshot.text,
                    searchText: searchText,
                    filtersMatches: filtersMatches,
                    followsLogs: followsLogs
                )
            }
        }
    }

    private var expandedLogSheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(logSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    isExpanded = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(.bar)

            expandedControls

            Divider()

            logContent(currentLogState)
        }
        .frame(width: expandedSheetSize.width, height: expandedSheetSize.height)
    }

    private var expandedControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Toggle("Timestamps", isOn: $showsTimestamps)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Toggle("Previous", isOn: $showsPreviousLogs)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Toggle("Live", isOn: $followsLogs)
                    .toggleStyle(.checkbox)
                    .disabled(showsPreviousLogs)
                    .fixedSize()

                HStack(spacing: 6) {
                    Text("Tail")
                        .foregroundStyle(.secondary)

                    Picker("Tail", selection: $tailSelection) {
                        ForEach(LogTailSelection.allCases) { selection in
                            Text(selection.title).tag(selection)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 105)
                    .disabled(followsLogs)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search logs", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260, idealWidth: 360)

                    Toggle("Grep", isOn: $filtersMatches)
                        .toggleStyle(.checkbox)
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fixedSize()
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 10) {
                Spacer()

                Button {
                    refreshLogs()
                } label: {
                    Label("Refresh Logs", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    saveDisplayedLogs()
                } label: {
                    Label("Save Displayed", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(isSavingLogs || displayedLogTextForCurrentState.isEmpty)

                Button {
                    Task {
                        await downloadAllLogs()
                    }
                } label: {
                    Label("Download All", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .disabled(isSavingLogs || appModel.selectedConnectionState != .connected)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var containerNames: [String] {
        summary.containers.map(\.name)
    }

    private var isPod: Bool {
        row.kind == "Pod" || summary.kind == "Pod"
    }

    private var selectedContainerForRequest: String? {
        guard containerNames.count > 1 else {
            return nil
        }

        if containerNames.contains(selectedContainerName) {
            return selectedContainerName
        }

        return containerNames.first
    }

    private var expandedSheetSize: CGSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(
            width: max(1_180, visibleFrame.width * 0.88),
            height: max(720, visibleFrame.height * 0.86)
        )
    }

    private var logSubtitle: String {
        let namespace = row.displayNamespace == "-" ? "cluster scoped" : row.displayNamespace
        let scope = showsPreviousLogs ? "previous" : "current"
        let mode = followsLogs ? "live" : tailSelection.subtitle
        if let containerName = selectedContainerForRequest {
            return "\(namespace) - \(containerName) - \(scope) - \(mode)"
        }

        return "\(namespace) - \(scope) - \(mode)"
    }

    private var currentLogState: PodLogLoadState {
        appModel.podLogState(
            for: row,
            containerName: selectedContainerForRequest,
            timestamps: showsTimestamps,
            previous: showsPreviousLogs,
            tailLines: tailSelection.lineCount,
            follow: followsLogs
        )
    }

    private var currentTaskID: String {
        appModel.podLogTaskID(
            for: row,
            containerName: selectedContainerForRequest,
            timestamps: showsTimestamps,
            previous: showsPreviousLogs,
            tailLines: tailSelection.lineCount,
            follow: followsLogs
        )
    }

    private func refreshLogs() {
        appModel.loadPodLogs(
            for: row,
            containerName: selectedContainerForRequest,
            timestamps: showsTimestamps,
            previous: showsPreviousLogs,
            tailLines: tailSelection.lineCount,
            follow: followsLogs,
            force: true
        )
    }

    private func statusText(for snapshot: PodLogSnapshot) -> String {
        let displayLineCount = LogTextSurface.lines(
            in: snapshot.text,
            searchText: searchText,
            filtersMatches: filtersMatches
        ).count
        let totalLineCount = LogTextSurface.lines(
            in: snapshot.text,
            searchText: "",
            filtersMatches: false
        ).count
        let loadedText = followsLogs ? "Streaming" : "Loaded"
        if displayLineCount == totalLineCount {
            return "\(loadedText) \(snapshot.loadedAt.formatted(date: .omitted, time: .standard)) - \(totalLineCount) lines"
        }

        return "\(loadedText) \(snapshot.loadedAt.formatted(date: .omitted, time: .standard)) - \(displayLineCount)/\(totalLineCount) lines"
    }

    private func displayedLogText(_ text: String) -> String {
        LogTextSurface.lines(
            in: text,
            searchText: searchText,
            filtersMatches: filtersMatches
        )
        .joined(separator: "\n")
    }

    private var displayedLogTextForCurrentState: String {
        guard case .loaded(let snapshot) = currentLogState else {
            return ""
        }

        return displayedLogText(snapshot.text)
    }

    private func saveDisplayedLogs() {
        let text = displayedLogTextForCurrentState
        guard !text.isEmpty,
              let url = chooseLogSaveURL(kind: "displayed") else {
            return
        }

        do {
            try writeLogText(text, to: url)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func downloadAllLogs() async {
        guard let url = chooseLogSaveURL(kind: "all") else {
            return
        }

        isSavingLogs = true
        defer {
            isSavingLogs = false
        }

        do {
            let text = try await appModel.podLogsText(
                for: row,
                containerName: selectedContainerForRequest,
                timestamps: showsTimestamps,
                previous: showsPreviousLogs,
                tailLines: nil
            )
            try writeLogText(text, to: url)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func chooseLogSaveURL(kind: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultLogFilename(kind: kind)

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    private func writeLogText(_ text: String, to url: URL) throws {
        let normalizedText = text.hasSuffix("\n") ? text : text + "\n"
        try normalizedText.write(to: url, atomically: true, encoding: .utf8)
    }

    private func defaultLogFilename(kind: String) -> String {
        let container = selectedContainerForRequest.map { "-\($0)" } ?? ""
        let previous = showsPreviousLogs ? "-previous" : ""
        return "\(sanitizedFilenameComponent(row.displayName))\(sanitizedFilenameComponent(container))\(previous)-\(kind).log"
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? scalar : UnicodeScalar("-")
        }
        let result = String(String.UnicodeScalarView(scalars))
        return result.isEmpty ? "logs" : result
    }

    private func reconcileContainer() {
        guard !containerNames.isEmpty else {
            selectedContainerName = ""
            return
        }

        if containerNames.contains(selectedContainerName) {
            return
        }

        selectedContainerName = containerNames.first ?? ""
    }
}

private enum LogTailSelection: String, CaseIterable, Identifiable {
    case last200
    case last1000
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .last200:
            "200"
        case .last1000:
            "1,000"
        case .all:
            "All"
        }
    }

    var subtitle: String {
        switch self {
        case .last200:
            "tail 200 lines"
        case .last1000:
            "tail 1,000 lines"
        case .all:
            "all logs"
        }
    }

    var lineCount: Int? {
        switch self {
        case .last200:
            200
        case .last1000:
            1_000
        case .all:
            nil
        }
    }
}

private struct LogTextSurface: View {
    let text: String
    let searchText: String
    let filtersMatches: Bool
    let followsLogs: Bool

    private var displayedLines: [String] {
        Self.lines(in: text, searchText: searchText, filtersMatches: filtersMatches)
    }

    private var displayedText: String {
        displayedLines.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if text.isEmpty {
                EmptyStateView(
                    title: "No Log Lines",
                    subtitle: "Kubernetes returned an empty log response for this Pod.",
                    systemImage: "terminal"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else if displayedLines.isEmpty {
                EmptyStateView(
                    title: "No Matches",
                    subtitle: "No log lines match the current search.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                SelectableLogTextView(
                    text: displayedText,
                    searchText: searchText,
                    followsLogs: followsLogs
                )
                .accessibilityIdentifier("resource.detail.logs.text")
            }
        }
    }

    static func lines(
        in text: String,
        searchText: String,
        filtersMatches: Bool
    ) -> [String] {
        var lines = text.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filtersMatches, !needle.isEmpty else {
            return lines
        }

        return lines.filter { line in
            line.range(of: needle, options: [.caseInsensitive]) != nil
        }
    }
}

private struct SelectableLogTextView: NSViewRepresentable {
    let text: String
    let searchText: String
    let followsLogs: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.coordinator.text != text || context.coordinator.searchText != needle {
            textView.textStorage?.setAttributedString(Self.attributedText(text, searchText: needle))
            context.coordinator.text = text
            context.coordinator.searchText = needle
        }

        if followsLogs {
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }

    private static func attributedText(_ text: String, searchText: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let result = NSMutableAttributedString(string: text, attributes: attributes)

        guard !searchText.isEmpty else {
            return result
        }

        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.length > 0 {
            let matchRange = nsText.range(
                of: searchText,
                options: [.caseInsensitive],
                range: searchRange
            )
            if matchRange.location == NSNotFound {
                break
            }

            result.addAttributes(
                [
                    .backgroundColor: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22),
                    .foregroundColor: NSColor.controlAccentColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
                ],
                range: matchRange
            )

            let nextLocation = matchRange.location + matchRange.length
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return result
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var text = ""
        var searchText = ""
    }
}

private struct ResourceEventCard: View {
    let event: KubernetesResourceEventSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ResourceEventTypePill(type: event.type)

                Text(event.reason)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let count = event.count, count > 1 {
                    Text("\(count)x")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(event.ageDescription())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(event.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if let source = event.source, !source.isEmpty {
                    Label(source, systemImage: "antenna.radiowaves.left.and.right")
                }

                if let involvedText, !involvedText.isEmpty {
                    Label(involvedText, systemImage: "scope")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderTint.opacity(0.22))
        }
    }

    private var involvedText: String? {
        let object = [
            event.involvedKind,
            event.involvedNamespace,
            event.involvedName
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " / ")

        if let fieldPath = event.involvedFieldPath, !fieldPath.isEmpty {
            return object.isEmpty ? fieldPath : "\(object) / \(fieldPath)"
        }

        return object.isEmpty ? nil : object
    }

    private var borderTint: Color {
        event.type.localizedCaseInsensitiveContains("warning") ? .orange : .secondary
    }
}

private struct ResourceEventTypePill: View {
    let type: String

    var body: some View {
        Text(type.isEmpty ? "-" : type)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var tint: Color {
        type.localizedCaseInsensitiveContains("warning") ? .orange : .green
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

private struct ResourceDetailEnvironmentView: View {
    let summary: KubernetesResourceDetailSummary

    var body: some View {
        Group {
            if summary.environment.isEmpty {
                EmptyStateView(
                    title: "No Environment",
                    subtitle: "This resource does not define container environment variables.",
                    systemImage: "switch.2"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(summary.environment) { container in
                            SectionSurface(title: container.containerName, systemImage: "shippingbox") {
                                VStack(spacing: 0) {
                                    ForEach(Array(container.variables.enumerated()), id: \.element.id) { index, variable in
                                        ResourceEnvironmentVariableRow(
                                            variable: variable,
                                            namespace: summary.namespace
                                        )

                                        if index < container.variables.count - 1 || !container.envFrom.isEmpty {
                                            Divider()
                                        }
                                    }

                                    ForEach(Array(container.envFrom.enumerated()), id: \.element.id) { index, source in
                                        ResourceEnvironmentFromRow(source: source)

                                        if index < container.envFrom.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .accessibilityIdentifier("resource.detail.environment")
    }
}

private struct ResourceEnvironmentVariableRow: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isRevealed = false

    let variable: KubernetesEnvVarSummary
    let namespace: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(variable.name)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)

                Text(sourceDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(width: 220, alignment: .leading)

            valueView
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasRevealControl {
                Button {
                    toggleReveal()
                } label: {
                    Label(revealTitle, systemImage: isRevealed ? "eye.slash" : "eye")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!canReveal)
                .help(revealTitle)
            }
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var valueView: some View {
        if let source = variable.source, source.kind == .secretKeyRef {
            secretValueView(source)
        } else if let literalValue = variable.literalValue {
            Text(literalValue)
                .font(.callout.monospaced())
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        } else {
            Text(sourceValuePlaceholder)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func secretValueView(_ source: KubernetesEnvVarSourceSummary) -> some View {
        if isRevealed {
            switch appModel.envSecretValueState(
                namespace: namespace,
                secretName: source.name,
                key: source.key
            ) {
            case .idle:
                Text(maskedValue)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value):
                Text(value)
                    .font(.callout.monospaced())
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        } else {
            Text(maskedValue)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var sourceDescription: String {
        guard let source = variable.source else {
            return "Literal"
        }

        switch source.kind {
        case .secretKeyRef:
            return "Secret \(source.name ?? "-") · \(source.key ?? "-")"
        case .configMapKeyRef:
            return "ConfigMap \(source.name ?? "-") · \(source.key ?? "-")"
        case .fieldRef:
            return "Field \(source.fieldPath ?? "-")"
        case .resourceFieldRef:
            return "Resource \(source.resource ?? "-")"
        case .unknown:
            return "Value reference"
        }
    }

    private var sourceValuePlaceholder: String {
        guard let source = variable.source else {
            return "-"
        }

        switch source.kind {
        case .configMapKeyRef:
            return "from ConfigMap"
        case .fieldRef:
            return source.fieldPath ?? "from field"
        case .resourceFieldRef:
            return source.resource ?? "from resource"
        case .secretKeyRef:
            return maskedValue
        case .unknown:
            return "from reference"
        }
    }

    private var hasRevealControl: Bool {
        variable.source?.kind == .secretKeyRef
    }

    private var canReveal: Bool {
        guard let source = variable.source, source.kind == .secretKeyRef else {
            return false
        }

        return namespace?.isEmpty == false &&
            source.name?.isEmpty == false &&
            source.key?.isEmpty == false
    }

    private var revealTitle: String {
        isRevealed ? "Hide Value" : "Reveal Value"
    }

    private var maskedValue: String {
        "••••••••"
    }

    private func toggleReveal() {
        if isRevealed {
            isRevealed = false
            return
        }

        isRevealed = true
        guard let source = variable.source, source.kind == .secretKeyRef else {
            return
        }

        appModel.revealEnvSecretValue(
            namespace: namespace,
            secretName: source.name,
            key: source.key
        )
    }
}

private struct ResourceEnvironmentFromRow: View {
    let source: KubernetesEnvFromSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.prefix.map { "\($0)*" } ?? "*")
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)

                Text(sourceDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(width: 220, alignment: .leading)

            Text(valueDescription)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private var sourceDescription: String {
        switch source.kind {
        case .secretRef:
            return "Secret \(source.name)"
        case .configMapRef:
            return "ConfigMap \(source.name)"
        }
    }

    private var valueDescription: String {
        switch source.kind {
        case .secretRef:
            return "all secret keys"
        case .configMapRef:
            return "all config keys"
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
        .appSurface()
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
