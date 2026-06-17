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
    @State private var visibleRowOrder: [KubernetesUnstructuredResource.ID] = []
    @State private var rowResourceVersions: [KubernetesUnstructuredResource.ID: String] = [:]
    @State private var recentlyUpdatedRowIDs: Set<KubernetesUnstructuredResource.ID> = []
    @State private var rowUpdateClearTasks: [KubernetesUnstructuredResource.ID: Task<Void, Never>] = [:]

    let item: ResourceNavigationItem

    private static let rowUpdateHighlightDurationNanoseconds: UInt64 = 1_600_000_000

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
        let visibleRowIDs = visibleRows.map(\.id)
        let allRows = snapshot.items
        let rowVersionSignatures = resourceVersionSignatures(for: allRows)
        Group {
            if openDetailRows.isEmpty {
                resourceListSurface(visibleRows: visibleRows, snapshot: snapshot)
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
            }
        }
        .onAppear {
            visibleRowOrder = visibleRowIDs
            seedRowResourceVersions(allRows)
            reconcileDetailTabs(with: allRows)
        }
        .onChange(of: visibleRowIDs) {
            visibleRowOrder = visibleRowIDs
        }
        .onChange(of: rowVersionSignatures) {
            markRecentlyUpdatedRows(allRows)
        }
        .onChange(of: allRows.map(\.id)) {
            reconcileDetailTabs(with: allRows)
        }
        .onDisappear {
            cancelRowUpdateClearTasks()
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
                if item == .pods {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 280, ideal: 340)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Ready", value: \.podReadySortValue) { resource in
                        ResourcePodReadyCell(resource: resource)
                    }
                    .width(min: 72, ideal: 86, max: 110)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourcePodStatusCell(resource: resource)
                    }
                    .width(min: 150, ideal: 180)
                    TableColumn("Restarts", value: \.podRestartCount) { resource in
                        Text(resource.podRestartCountDescription)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(resource.podRestartCount > 0 ? .orange : .secondary)
                    }
                    .width(min: 82, ideal: 96, max: 120)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else if item == .deployments {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 260, ideal: 320)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Ready", value: \.deploymentReadySortValue) { resource in
                        ResourceReplicaCountCell(
                            value: resource.deploymentReadyDescription,
                            isHealthy: resource.deploymentReadyReplicas >= resource.deploymentDesiredReplicas,
                            isUnhealthy: resource.isDeploymentUnhealthy,
                            help: "Ready replicas: \(resource.deploymentReadyDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Up-to-date", value: \.deploymentUpdatedSortValue) { resource in
                        ResourceReplicaCountCell(
                            value: resource.deploymentUpdatedDescription,
                            isHealthy: resource.deploymentUpdatedReplicas >= resource.deploymentDesiredReplicas,
                            isUnhealthy: false,
                            help: "Updated replicas: \(resource.deploymentUpdatedDescription)"
                        )
                    }
                    .width(min: 92, ideal: 112, max: 136)
                    TableColumn("Available", value: \.deploymentAvailableSortValue) { resource in
                        ResourceReplicaCountCell(
                            value: resource.deploymentAvailableDescription,
                            isHealthy: resource.deploymentAvailableReplicas >= resource.deploymentDesiredReplicas,
                            isUnhealthy: resource.isDeploymentUnhealthy,
                            help: "Available replicas: \(resource.deploymentAvailableDescription)"
                        )
                    }
                    .width(min: 86, ideal: 106, max: 130)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourceDeploymentStatusCell(resource: resource)
                    }
                    .width(min: 150, ideal: 190)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else if item == .replicaSets {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 280, ideal: 340)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Desired", value: \.replicaSetDesiredReplicas) { resource in
                        ResourceReplicaCountCell(
                            value: resource.replicaSetDesiredDescription,
                            isHealthy: true,
                            isUnhealthy: false,
                            help: "Desired replicas: \(resource.replicaSetDesiredDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Current", value: \.replicaSetCurrentReplicas) { resource in
                        ResourceReplicaCountCell(
                            value: resource.replicaSetCurrentDescription,
                            isHealthy: resource.replicaSetCurrentReplicas >= resource.replicaSetDesiredReplicas,
                            isUnhealthy: resource.isReplicaSetUnhealthy,
                            help: "Current replicas: \(resource.replicaSetCurrentDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Ready", value: \.replicaSetReadyReplicas) { resource in
                        ResourceReplicaCountCell(
                            value: resource.replicaSetReadyDescription,
                            isHealthy: resource.replicaSetReadyReplicas >= resource.replicaSetDesiredReplicas,
                            isUnhealthy: resource.isReplicaSetUnhealthy,
                            help: "Ready replicas: \(resource.replicaSetReadyDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourceReplicaSetStatusCell(resource: resource)
                    }
                    .width(min: 150, ideal: 190)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else if item == .statefulSets {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 280, ideal: 340)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Ready", value: \.statefulSetReadySortValue) { resource in
                        ResourceReplicaCountCell(
                            value: resource.statefulSetReadyDescription,
                            isHealthy: resource.statefulSetReadyReplicas >= resource.statefulSetDesiredReplicas,
                            isUnhealthy: resource.isStatefulSetUnhealthy,
                            help: "Ready replicas: \(resource.statefulSetReadyDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Current", value: \.statefulSetCurrentSortValue) { resource in
                        ResourceReplicaCountCell(
                            value: resource.statefulSetCurrentDescription,
                            isHealthy: resource.statefulSetCurrentReplicas >= resource.statefulSetDesiredReplicas,
                            isUnhealthy: false,
                            help: "Current replicas: \(resource.statefulSetCurrentDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Updated", value: \.statefulSetUpdatedSortValue) { resource in
                        ResourceReplicaCountCell(
                            value: resource.statefulSetUpdatedDescription,
                            isHealthy: resource.statefulSetUpdatedReplicas >= resource.statefulSetDesiredReplicas,
                            isUnhealthy: false,
                            help: "Updated replicas: \(resource.statefulSetUpdatedDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourceStatefulSetStatusCell(resource: resource)
                    }
                    .width(min: 150, ideal: 190)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else if item == .daemonSets {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 280, ideal: 340)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Desired", value: \.daemonSetDesiredNumberScheduled) { resource in
                        ResourceReplicaCountCell(
                            value: resource.daemonSetDesiredDescription,
                            isHealthy: true,
                            isUnhealthy: false,
                            help: "Desired scheduled pods: \(resource.daemonSetDesiredDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Current", value: \.daemonSetCurrentNumberScheduled) { resource in
                        ResourceReplicaCountCell(
                            value: resource.daemonSetCurrentDescription,
                            isHealthy: resource.daemonSetCurrentNumberScheduled >= resource.daemonSetDesiredNumberScheduled,
                            isUnhealthy: false,
                            help: "Current scheduled pods: \(resource.daemonSetCurrentDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Ready", value: \.daemonSetNumberReady) { resource in
                        ResourceReplicaCountCell(
                            value: resource.daemonSetReadyDescription,
                            isHealthy: resource.daemonSetNumberReady >= resource.daemonSetDesiredNumberScheduled,
                            isUnhealthy: resource.isDaemonSetUnhealthy,
                            help: "Ready pods: \(resource.daemonSetReadyDescription)"
                        )
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Available", value: \.daemonSetNumberAvailable) { resource in
                        ResourceReplicaCountCell(
                            value: resource.daemonSetAvailableDescription,
                            isHealthy: resource.daemonSetNumberAvailable >= resource.daemonSetDesiredNumberScheduled,
                            isUnhealthy: resource.isDaemonSetUnhealthy,
                            help: "Available pods: \(resource.daemonSetAvailableDescription)"
                        )
                    }
                    .width(min: 86, ideal: 106, max: 130)
                    TableColumn("Misscheduled", value: \.daemonSetNumberMisscheduled) { resource in
                        ResourceReplicaCountCell(
                            value: resource.daemonSetMisscheduledDescription,
                            isHealthy: resource.daemonSetNumberMisscheduled == 0,
                            isUnhealthy: resource.daemonSetNumberMisscheduled > 0,
                            help: "Misscheduled pods: \(resource.daemonSetMisscheduledDescription)"
                        )
                    }
                    .width(min: 104, ideal: 124, max: 148)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourceDaemonSetStatusCell(resource: resource)
                    }
                    .width(min: 150, ideal: 190)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else if item == .jobs {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 260, ideal: 320)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Complete", value: \.jobCompletionSortValue) { resource in
                        ResourceJobCompletionCell(resource: resource)
                    }
                    .width(min: 86, ideal: 104, max: 130)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourceJobStatusCell(resource: resource)
                    }
                    .width(min: 140, ideal: 170)
                    TableColumn("Failures", value: \.jobFailedCount) { resource in
                        Text(resource.jobFailedDescription)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(resource.jobFailedCount > 0 ? .red : .secondary)
                    }
                    .width(min: 82, ideal: 100, max: 124)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else if item == .cronJobs {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 260, ideal: 320)

                    TableColumn("Namespace", value: \.displayNamespace)
                        .width(min: 150, ideal: 180)
                    TableColumn("Schedule", value: \.cronJobScheduleDescription) { resource in
                        Text(resource.cronJobScheduleDescription)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .help("Schedule: \(resource.cronJobScheduleDescription)")
                    }
                    .width(min: 118, ideal: 150)
                    TableColumn("Suspend", value: \.cronJobSuspendDescription) { resource in
                        Text(resource.cronJobSuspendDescription)
                            .font(.callout.weight(resource.isCronJobSuspended ? .semibold : .regular))
                            .foregroundStyle(resource.isCronJobSuspended ? .orange : .secondary)
                            .help(resource.isCronJobSuspended ? "CronJob is suspended" : "CronJob is not suspended")
                    }
                    .width(min: 78, ideal: 96, max: 118)
                    TableColumn("Active", value: \.cronJobActiveCount) { resource in
                        ResourceReplicaCountCell(
                            value: resource.cronJobActiveDescription,
                            isHealthy: resource.cronJobActiveCount == 0,
                            isUnhealthy: false,
                            help: "Active jobs: \(resource.cronJobActiveDescription)"
                        )
                    }
                    .width(min: 72, ideal: 88, max: 110)
                    TableColumn("Last Schedule", value: \.cronJobLastScheduleSortValue) { resource in
                        Text(resource.cronJobLastScheduleDescription())
                            .foregroundStyle(resource.cronJobLastScheduleDate == nil ? .secondary : .primary)
                            .help("Last schedule: \(resource.cronJobLastScheduleDescription())")
                    }
                    .width(min: 112, ideal: 140, max: 170)
                    TableColumn("Last Success", value: \.cronJobLastSuccessfulSortValue) { resource in
                        Text(resource.cronJobLastSuccessfulDescription())
                            .foregroundStyle(resource.cronJobLastSuccessfulDate == nil ? .secondary : .primary)
                            .help("Last successful run: \(resource.cronJobLastSuccessfulDescription())")
                    }
                    .width(min: 108, ideal: 136, max: 166)
                    TableColumn("Status", value: \.displayStatus) { resource in
                        ResourceCronJobStatusCell(resource: resource)
                    }
                    .width(min: 140, ideal: 170)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    .width(min: 72, ideal: 90, max: 120)
                } else {
                    TableColumn("Name", value: \.displayName) { resource in
                        ResourceNameCell(
                            resource: resource,
                            isRecentlyUpdated: recentlyUpdatedRowIDs.contains(resource.id),
                            density: appModel.tableDensity
                        )
                    }
                    .width(min: 220, ideal: 280)

                    TableColumn("Namespace", value: \.displayNamespace)
                    TableColumn("Kind", value: \.displayKind)
                    TableColumn("Status", value: \.displayStatus)
                    TableColumn("Age") { resource in
                        Text(resource.ageDescription())
                    }
                    TableColumn("Labels", value: \.labelsSummary)
                }
            }
            .tableStyle(.inset)
            .font(appModel.tableDensity.tableFont)
            .controlSize(appModel.tableDensity.controlSize)
            .environment(\.defaultMinListRowHeight, appModel.tableDensity.rowHeight)
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

            if item == .pods, let labelFilter = appModel.resourceLabelFilter {
                ResourceLabelFilterBadge(filter: labelFilter) {
                    appModel.clearResourceLabelFilter()
                }
            }

            if let ownerFilter = appModel.resourceOwnerFilter,
               ownerFilter.targetResource == item {
                ResourceOwnerFilterBadge(filter: ownerFilter) {
                    appModel.clearResourceOwnerFilter()
                }
            }

            if let nameFilter = appModel.resourceNameFilter,
               nameFilter.targetResource == item {
                ResourceNameFilterBadge(filter: nameFilter) {
                    appModel.clearResourceNameFilter()
                }
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
        if item == .pods, let labelFilter = appModel.resourceLabelFilter {
            return "No pods match \(labelFilter.detail)."
        }

        if let ownerFilter = appModel.resourceOwnerFilter,
           ownerFilter.targetResource == item {
            return "No \(item.title.lowercased()) are owned by \(ownerFilter.detail)."
        }

        if let nameFilter = appModel.resourceNameFilter,
           nameFilter.targetResource == item {
            return "No \(item.title.lowercased()) match \(nameFilter.detail)."
        }

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
        let labelFilteredRows: [KubernetesUnstructuredResource]
        if item == .pods, let labelFilter = appModel.resourceLabelFilter {
            labelFilteredRows = snapshot.items.filter { labelFilter.matches($0) }
        } else {
            labelFilteredRows = snapshot.items
        }

        let relationshipFilteredRows: [KubernetesUnstructuredResource]
        if let ownerFilter = appModel.resourceOwnerFilter,
           ownerFilter.targetResource == item {
            relationshipFilteredRows = labelFilteredRows.filter { ownerFilter.matches($0) }
        } else {
            relationshipFilteredRows = labelFilteredRows
        }

        let nameFilteredRows: [KubernetesUnstructuredResource]
        if let nameFilter = appModel.resourceNameFilter,
           nameFilter.targetResource == item {
            nameFilteredRows = relationshipFilteredRows.filter { nameFilter.matches($0) }
        } else {
            nameFilteredRows = relationshipFilteredRows
        }

        let rows = searchText.isEmpty
            ? nameFilteredRows
            : nameFilteredRows.filter { $0.searchBlob.contains(searchText) }

        return ResourceListRowOrdering.orderedRows(
            rows,
            sortOrder: sortOrder,
            preservedOrderIDs: visibleRowOrder,
            preserveExistingOrder: shouldPreserveVisibleRowOrder
        )
    }

    private var shouldPreserveVisibleRowOrder: Bool {
        selectedResourceID != nil || !openDetailRows.isEmpty
    }

    private func resourceVersionSignatures(
        for rows: [KubernetesUnstructuredResource]
    ) -> [ResourceRowVersionSignature] {
        rows.map {
            ResourceRowVersionSignature(
                id: $0.id,
                resourceVersion: $0.metadata.resourceVersion
            )
        }
    }

    private func seedRowResourceVersions(_ rows: [KubernetesUnstructuredResource]) {
        rowResourceVersions = rows.reduce(into: [:]) { resourceVersions, row in
            resourceVersions[row.id] = row.metadata.resourceVersion ?? ""
        }
        recentlyUpdatedRowIDs = []
        cancelRowUpdateClearTasks()
    }

    private func markRecentlyUpdatedRows(_ rows: [KubernetesUnstructuredResource]) {
        let rowIDs = Set(rows.map(\.id))
        var nextResourceVersions = rowResourceVersions.filter { rowIDs.contains($0.key) }
        var updatedIDs = Set<KubernetesUnstructuredResource.ID>()

        for row in rows {
            let resourceVersion = row.metadata.resourceVersion ?? ""
            if let previousResourceVersion = rowResourceVersions[row.id],
               previousResourceVersion != resourceVersion {
                updatedIDs.insert(row.id)
            }
            nextResourceVersions[row.id] = resourceVersion
        }

        rowResourceVersions = nextResourceVersions

        guard !updatedIDs.isEmpty else {
            return
        }

        withAnimation(.easeOut(duration: 0.16)) {
            recentlyUpdatedRowIDs.formUnion(updatedIDs)
        }

        for id in updatedIDs {
            scheduleRowUpdateHighlightClear(id)
        }
    }

    private func scheduleRowUpdateHighlightClear(_ id: KubernetesUnstructuredResource.ID) {
        rowUpdateClearTasks[id]?.cancel()
        rowUpdateClearTasks[id] = Task {
            do {
                try await Task.sleep(nanoseconds: Self.rowUpdateHighlightDurationNanoseconds)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.28)) {
                        _ = recentlyUpdatedRowIDs.remove(id)
                    }
                    rowUpdateClearTasks[id] = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    rowUpdateClearTasks[id] = nil
                }
            } catch {
                await MainActor.run {
                    rowUpdateClearTasks[id] = nil
                }
            }
        }
    }

    private func cancelRowUpdateClearTasks() {
        for task in rowUpdateClearTasks.values {
            task.cancel()
        }
        rowUpdateClearTasks = [:]
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

private struct ResourceRowVersionSignature: Equatable {
    var id: KubernetesUnstructuredResource.ID
    var resourceVersion: String?
}

private struct ResourceNameCell: View {
    let resource: KubernetesUnstructuredResource
    let isRecentlyUpdated: Bool
    let density: TableDensity

    var body: some View {
        HStack(spacing: density.nameCellSpacing) {
            Text(resource.displayName)
                .lineLimit(1)

            ZStack {
                Circle()
                    .fill(.green.opacity(0.16))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isRecentlyUpdated ? 1 : 0.72)

                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
            }
            .opacity(isRecentlyUpdated ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: isRecentlyUpdated)
            .frame(width: 10, height: 10)
            .help("Updated by live watch")
            .accessibilityLabel("Recently updated")
            .accessibilityHidden(!isRecentlyUpdated)
        }
    }
}

private extension TableDensity {
    var rowHeight: CGFloat {
        switch self {
        case .compact:
            22
        case .comfortable:
            28
        case .spacious:
            36
        }
    }

    var tableFont: Font {
        switch self {
        case .compact:
            .callout
        case .comfortable:
            .body
        case .spacious:
            .body
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .compact:
            .small
        case .comfortable:
            .regular
        case .spacious:
            .large
        }
    }

    var nameCellSpacing: CGFloat {
        switch self {
        case .compact:
            5
        case .comfortable:
            7
        case .spacious:
            9
        }
    }
}

private struct ResourcePodStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isPodUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isPodUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isPodUnhealthy ? 3 : 0)
        .background {
            if resource.isPodUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isPodUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if status.contains("crashloop") ||
            status.contains("failed") ||
            status.contains("error") ||
            status.contains("errimagepull") ||
            status.contains("invalidimage") {
            return .red
        }

        if status.contains("backoff") ||
            status.contains("pending") ||
            status.contains("terminating") ||
            status.contains("containercreating") {
            return .orange
        }

        if status.contains("succeeded") || status.contains("completed") {
            return .secondary
        }

        return .green
    }

    private var systemImage: String {
        let status = resource.displayStatus.lowercased()
        if resource.isPodUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        if status.contains("succeeded") || status.contains("completed") {
            return "checkmark.circle"
        }

        if status.contains("pending") || status.contains("terminating") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isPodUnhealthy {
            return "Pod status needs attention: \(resource.displayStatus)"
        }

        return "Pod status: \(resource.displayStatus)"
    }
}

private struct ResourcePodReadyCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        Text(resource.podReadyDescription)
            .font(.callout.monospacedDigit().weight(isEmphasized ? .semibold : .regular))
            .foregroundStyle(tint)
            .help("Ready containers: \(resource.podReadyDescription)")
    }

    private var isEmphasized: Bool {
        resource.isPodUnhealthy && resource.podReadyCount < resource.podContainerCount
    }

    private var tint: Color {
        if resource.podReadyDescription == "-" {
            return .secondary
        }

        let status = resource.displayStatus.lowercased()
        if status.contains("succeeded") || status.contains("completed") {
            return .secondary
        }

        if resource.podReadyCount == resource.podContainerCount {
            return .green
        }

        return resource.isPodUnhealthy ? .red : .orange
    }
}

private struct ResourceReplicaCountCell: View {
    let value: String
    let isHealthy: Bool
    let isUnhealthy: Bool
    let help: String

    var body: some View {
        Text(value)
            .font(.callout.monospacedDigit().weight(isHealthy ? .regular : .semibold))
            .foregroundStyle(tint)
            .help(help)
    }

    private var tint: Color {
        if isHealthy {
            return .green
        }

        return isUnhealthy ? .red : .orange
    }
}

private struct ResourceReplicaSetStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isReplicaSetUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isReplicaSetUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isReplicaSetUnhealthy ? 3 : 0)
        .background {
            if resource.isReplicaSetUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isReplicaSetUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if resource.isReplicaSetUnhealthy {
            return .red
        }

        if status.contains("scaling") || status.contains("scaled") {
            return .orange
        }

        return .green
    }

    private var systemImage: String {
        let status = resource.displayStatus.lowercased()
        if resource.isReplicaSetUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        if status.contains("scaling") || status.contains("scaled") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isReplicaSetUnhealthy {
            return "ReplicaSet status needs attention: \(resource.displayStatus)"
        }

        return "ReplicaSet status: \(resource.displayStatus)"
    }
}

private struct ResourceDaemonSetStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isDaemonSetUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isDaemonSetUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isDaemonSetUnhealthy ? 3 : 0)
        .background {
            if resource.isDaemonSetUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isDaemonSetUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if resource.isDaemonSetUnhealthy {
            return .red
        }

        if status.contains("scheduling") || status.contains("updating") || status.contains("no nodes") {
            return .orange
        }

        return .green
    }

    private var systemImage: String {
        let status = resource.displayStatus.lowercased()
        if resource.isDaemonSetUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        if status.contains("scheduling") || status.contains("updating") || status.contains("no nodes") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isDaemonSetUnhealthy {
            return "DaemonSet status needs attention: \(resource.displayStatus)"
        }

        return "DaemonSet status: \(resource.displayStatus)"
    }
}

private struct ResourceStatefulSetStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isStatefulSetUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isStatefulSetUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isStatefulSetUnhealthy ? 3 : 0)
        .background {
            if resource.isStatefulSetUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isStatefulSetUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if resource.isStatefulSetUnhealthy {
            return .red
        }

        if status.contains("updating") || status.contains("scaling") || status.contains("scaled") {
            return .orange
        }

        return .green
    }

    private var systemImage: String {
        let status = resource.displayStatus.lowercased()
        if resource.isStatefulSetUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        if status.contains("updating") || status.contains("scaling") || status.contains("scaled") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isStatefulSetUnhealthy {
            return "StatefulSet status needs attention: \(resource.displayStatus)"
        }

        return "StatefulSet status: \(resource.displayStatus)"
    }
}

private struct ResourceDeploymentStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isDeploymentUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isDeploymentUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isDeploymentUnhealthy ? 3 : 0)
        .background {
            if resource.isDeploymentUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isDeploymentUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if resource.isDeploymentUnhealthy {
            return .red
        }

        if status.contains("updating") || status.contains("scaled") {
            return .orange
        }

        return .green
    }

    private var systemImage: String {
        let status = resource.displayStatus.lowercased()
        if resource.isDeploymentUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        if status.contains("updating") || status.contains("scaled") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isDeploymentUnhealthy {
            return "Deployment status needs attention: \(resource.displayStatus)"
        }

        return "Deployment status: \(resource.displayStatus)"
    }
}

private struct ResourceCronJobStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isCronJobUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isCronJobUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isCronJobUnhealthy ? 3 : 0)
        .background {
            if resource.isCronJobUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isCronJobUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if resource.isCronJobUnhealthy {
            return .red
        }

        if status.contains("active") || status.contains("waiting") || status.contains("suspended") {
            return .orange
        }

        return .green
    }

    private var systemImage: String {
        let status = resource.displayStatus.lowercased()
        if resource.isCronJobUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        if status.contains("active") {
            return "play.circle.fill"
        }

        if status.contains("waiting") || status.contains("suspended") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isCronJobUnhealthy {
            return "CronJob status needs attention: \(resource.displayStatus)"
        }

        return "CronJob status: \(resource.displayStatus)"
    }
}

private struct ResourceJobCompletionCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        Text(resource.jobCompletionDescription)
            .font(.callout.monospacedDigit().weight(isComplete ? .regular : .semibold))
            .foregroundStyle(tint)
            .help("Job completions: \(resource.jobCompletionDescription)")
    }

    private var isComplete: Bool {
        resource.jobSucceededCount >= resource.jobCompletionTarget
    }

    private var tint: Color {
        if resource.isJobUnhealthy {
            return .red
        }

        return isComplete ? .green : .orange
    }
}

private struct ResourceJobStatusCell: View {
    let resource: KubernetesUnstructuredResource

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)

            Text(resource.displayStatus)
                .lineLimit(1)
                .foregroundStyle(titleColor)
        }
        .font(.callout.weight(resource.isJobUnhealthy ? .semibold : .regular))
        .padding(.horizontal, resource.isJobUnhealthy ? 7 : 0)
        .padding(.vertical, resource.isJobUnhealthy ? 3 : 0)
        .background {
            if resource.isJobUnhealthy {
                Capsule().fill(tint.opacity(0.14))
            }
        }
        .help(statusHelp)
    }

    private var titleColor: Color {
        resource.isJobUnhealthy ? tint : .primary
    }

    private var tint: Color {
        let status = resource.displayStatus.lowercased()
        if resource.isJobUnhealthy {
            return .red
        }

        if status.contains("running") || status.contains("pending") {
            return .orange
        }

        return .green
    }

    private var systemImage: String {
        if resource.isJobUnhealthy {
            return "exclamationmark.triangle.fill"
        }

        let status = resource.displayStatus.lowercased()
        if status.contains("running") || status.contains("pending") {
            return "clock"
        }

        return "checkmark.circle.fill"
    }

    private var statusHelp: String {
        if resource.isJobUnhealthy {
            return "Job status needs attention: \(resource.displayStatus)"
        }

        return "Job status: \(resource.displayStatus)"
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

private struct ResourceLabelFilterBadge: View {
    let filter: ResourceLabelFilter
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .imageScale(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(filter.title)
                    .lineLimit(1)
                Text(filter.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: clear) {
                Label("Clear Pod Filter", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear pod filter")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(.blue)
        .background(Color.blue.opacity(0.12), in: Capsule())
        .help("\(filter.title): \(filter.detail)")
        .accessibilityIdentifier("resource.list.pods.labelFilter")
    }
}

private struct ResourceOwnerFilterBadge: View {
    let filter: ResourceOwnerFilter
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .imageScale(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(filter.title)
                    .lineLimit(1)
                Text(filter.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: clear) {
                Label("Clear Owner Filter", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear owner filter")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(.blue)
        .background(Color.blue.opacity(0.12), in: Capsule())
        .help("\(filter.title): \(filter.detail)")
        .accessibilityIdentifier("resource.list.ownerFilter")
    }
}

private struct ResourceNameFilterBadge: View {
    let filter: ResourceNameFilter
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.right.circle")
                .imageScale(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(filter.title)
                    .lineLimit(1)
                Text(filter.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: clear) {
                Label("Clear Resource Filter", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear resource filter")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(.blue)
        .background(Color.blue.opacity(0.12), in: Capsule())
        .help("\(filter.title): \(filter.detail)")
        .accessibilityIdentifier("resource.list.nameFilter")
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
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .textSelection(.enabled)

                    Text(detailSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                if let detailStatusText {
                    ResourceDetailFreshnessBadge(
                        text: detailStatusText,
                        tint: detailStatusTint,
                        help: detailStatusHelp
                    )
                }

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

            ResourceDetailPanelTabBar(
                selection: $selectedPanel,
                isEnabled: isLoaded
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                loadedAt: snapshot.loadedAt,
                openOwner: { owner, namespace in
                    appModel.navigateToOwner(owner, namespace: namespace)
                },
                openPods: { selector, namespace, sourceTitle in
                    appModel.navigateToPods(
                        matching: selector,
                        sourceTitle: sourceTitle,
                        namespace: namespace
                    )
                },
                openOwnedResources: { owner, targetResource, namespace, sourceTitle in
                    appModel.navigateToOwnedResources(
                        owner: owner,
                        targetResource: targetResource,
                        sourceTitle: sourceTitle,
                        namespace: namespace
                    )
                },
                openNamedResource: { targetResource, name, namespace, sourceTitle in
                    appModel.navigateToResource(
                        targetResource,
                        name: name,
                        namespace: namespace,
                        sourceTitle: sourceTitle
                    )
                }
            )
        case .events:
            ResourceDetailEventsView(detail: snapshot)
        case .logs:
            ResourceDetailLogsView(row: row, summary: snapshot.summary)
        case .containers:
            ResourceDetailContainersView(summary: snapshot.summary)
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

    private var detailStatusText: String? {
        switch appModel.resourceDetailState(for: item, row: row) {
        case .loaded(let snapshot):
            if let rowResourceVersion = row.metadata.resourceVersion,
               !rowResourceVersion.isEmpty,
               snapshot.summary.resourceVersion != rowResourceVersion {
                return "Stale"
            }
            return "Updated \(snapshot.loadedAt.formatted(date: .omitted, time: .standard))"
        case .loading:
            return "Refreshing..."
        case .failed:
            return "Stale"
        case .idle:
            return nil
        }
    }

    private var detailStatusTint: Color {
        switch appModel.resourceDetailState(for: item, row: row) {
        case .loaded(let snapshot):
            if let rowResourceVersion = row.metadata.resourceVersion,
               !rowResourceVersion.isEmpty,
               snapshot.summary.resourceVersion != rowResourceVersion {
                return .orange
            }
            return .secondary
        case .loading:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var detailStatusHelp: String {
        switch appModel.resourceDetailState(for: item, row: row) {
        case .loaded(let snapshot):
            if let rowResourceVersion = row.metadata.resourceVersion,
               !rowResourceVersion.isEmpty,
               snapshot.summary.resourceVersion != rowResourceVersion {
                return "The list row has resourceVersion \(rowResourceVersion), but the loaded detail has \(snapshot.summary.resourceVersion ?? "-")."
            }
            return "Manifest loaded at \(snapshot.loadedAt.formatted(date: .omitted, time: .standard))."
        case .loading:
            return "Refreshing manifest for the current row."
        case .failed(let message):
            return "The current manifest could not be refreshed: \(message)"
        case .idle:
            return "Manifest has not loaded yet."
        }
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

private struct ResourceDetailFreshnessBadge: View {
    let text: String
    let tint: Color
    let help: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.monospacedDigit().weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .help(help)
            .accessibilityLabel(help)
    }

    private var systemImage: String {
        switch text {
        case "Refreshing...":
            "arrow.triangle.2.circlepath"
        case "Stale":
            "clock.badge.exclamationmark"
        default:
            "checkmark.circle"
        }
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
                .frame(maxWidth: .infinity)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
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
            .frame(minWidth: 74, maxWidth: .infinity)
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
    let openOwner: (KubernetesOwnerReferenceSummary, String?) -> Void
    let openPods: (KubernetesLabelSelectorSummary, String?, String) -> Void
    let openOwnedResources: (KubernetesOwnerReferenceSummary, ResourceNavigationItem, String?, String) -> Void
    let openNamedResource: (ResourceNavigationItem, String, String?, String) -> Void

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
                                ResourceOwnerSummaryRow(
                                    owner: owner,
                                    namespace: namespaceTextForOwner,
                                    openOwner: openOwner
                                )
                            }
                        }
                    }
                }

                if let labelSelector = summary.labelSelector {
                    SectionSurface(title: "Related Pods", systemImage: "square.stack.3d.up") {
                        ResourceRelatedPodsRow(
                            selector: labelSelector,
                            namespace: namespaceTextForOwner,
                            sourceTitle: sourceTitle,
                            openPods: openPods
                        )
                    }
                }

                if !relatedOwnedResourceActions.isEmpty {
                    SectionSurface(title: "Related Resources", systemImage: "point.3.connected.trianglepath.dotted") {
                        VStack(spacing: 0) {
                            ForEach(relatedOwnedResourceActions) { action in
                                ResourceRelatedOwnedResourcesRow(
                                    action: action,
                                    namespace: namespaceTextForOwner,
                                    sourceTitle: sourceTitle,
                                    openOwnedResources: openOwnedResources
                                )
                            }
                        }
                    }
                }

                if !summary.ingressServices.isEmpty {
                    SectionSurface(title: "Related Services", systemImage: "point.3.connected.trianglepath.dotted") {
                        VStack(spacing: 0) {
                            ForEach(summary.ingressServices) { backend in
                                ResourceRelatedNamedResourceRow(
                                    title: "Open Service",
                                    resource: .services,
                                    name: backend.name,
                                    detail: backend.route,
                                    namespace: namespaceTextForOwner,
                                    sourceTitle: sourceTitle,
                                    openNamedResource: openNamedResource
                                )
                            }
                        }
                    }
                }

                if let persistentVolumeName = summary.persistentVolumeName {
                    SectionSurface(title: "Related Storage", systemImage: "externaldrive") {
                        ResourceRelatedNamedResourceRow(
                            title: "Open PersistentVolume",
                            resource: .persistentVolumes,
                            name: persistentVolumeName,
                            detail: "Bound volume",
                            namespace: nil,
                            sourceTitle: sourceTitle,
                            openNamedResource: openNamedResource
                        )
                    }
                }

                if !summary.configMapReferences.isEmpty {
                    SectionSurface(title: "Related ConfigMaps", systemImage: "doc.text") {
                        VStack(spacing: 0) {
                            ForEach(summary.configMapReferences) { reference in
                                ResourceRelatedNamedResourceRow(
                                    title: "Open ConfigMap",
                                    resource: .configMaps,
                                    name: reference.name,
                                    detail: reference.detail,
                                    namespace: namespaceTextForOwner,
                                    sourceTitle: sourceTitle,
                                    openNamedResource: openNamedResource
                                )
                            }
                        }
                    }
                }

                if !summary.secretReferences.isEmpty {
                    SectionSurface(title: "Related Secrets", systemImage: "key") {
                        VStack(spacing: 0) {
                            ForEach(summary.secretReferences) { reference in
                                ResourceRelatedNamedResourceRow(
                                    title: "Open Secret",
                                    resource: .secrets,
                                    name: reference.name,
                                    detail: reference.detail,
                                    namespace: namespaceTextForOwner,
                                    sourceTitle: sourceTitle,
                                    openNamedResource: openNamedResource
                                )
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

    private var namespaceTextForOwner: String? {
        if let namespace = summary.namespace, !namespace.isEmpty {
            return namespace
        }

        return row.displayNamespace == "-" ? nil : row.displayNamespace
    }

    private var sourceTitle: String {
        "\(summary.kind ?? row.displayKind)/\(summary.name ?? row.displayName)"
    }

    private var relatedOwnedResourceActions: [ResourceOwnedRelationshipAction] {
        let name = summary.name ?? row.displayName
        guard !name.isEmpty else {
            return []
        }

        switch summary.kind ?? row.displayKind {
        case "Deployment":
            return [
                ResourceOwnedRelationshipAction(
                    title: "Show owned ReplicaSets",
                    owner: KubernetesOwnerReferenceSummary(kind: "Deployment", name: name, controller: true),
                    targetResource: .replicaSets
                )
            ]
        case "CronJob":
            return [
                ResourceOwnedRelationshipAction(
                    title: "Show owned Jobs",
                    owner: KubernetesOwnerReferenceSummary(kind: "CronJob", name: name, controller: true),
                    targetResource: .jobs
                )
            ]
        default:
            return []
        }
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
    @State private var sinceSelection: LogSinceSelection = .any
    @State private var followsLogs = false
    @State private var searchText = ""
    @State private var filtersMatches = false
    @State private var formatsJSONLines = false
    @State private var logViewIsPinnedToBottom = true
    @State private var jumpToLatestRequestID = 0
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
                logViewIsPinnedToBottom = true
                jumpToLatestRequestID += 1
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
                sinceSeconds: activeSinceSeconds,
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    logModeControls

                    Divider()
                        .frame(height: 18)

                    logSearchControls

                    Spacer()

                    logExportControls
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        logModeControls

                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 10) {
                        logSearchControls

                        Spacer(minLength: 8)

                        logExportControls
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var logModeControls: some View {
        HStack(spacing: 12) {
            Toggle("Timestamps", isOn: $showsTimestamps)
                .toggleStyle(.checkbox)

            Toggle("Previous", isOn: $showsPreviousLogs)
                .toggleStyle(.checkbox)
                .help("Show logs from the previously terminated container instance")

            Toggle("Live", isOn: $followsLogs)
                .toggleStyle(.checkbox)
                .disabled(showsPreviousLogs)

            Toggle("JSON", isOn: $formatsJSONLines)
                .toggleStyle(.checkbox)
                .help("Safely pretty-print JSON log lines")

            Picker("Tail", selection: $tailSelection) {
                ForEach(LogTailSelection.allCases) { selection in
                    Text(selection.title).tag(selection)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 96)
            .disabled(followsLogs)

            Picker("Since", selection: $sinceSelection) {
                ForEach(LogSinceSelection.allCases) { selection in
                    Text(selection.title).tag(selection)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 96)
            .disabled(followsLogs)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var logSearchControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search logs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, idealWidth: 240, maxWidth: 320)

            Toggle("Grep", isOn: $filtersMatches)
                .toggleStyle(.checkbox)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var logExportControls: some View {
        HStack(spacing: 10) {
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
        .fixedSize(horizontal: true, vertical: false)
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
                        sinceSeconds: activeSinceSeconds,
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

                    if !logViewIsPinnedToBottom {
                        Button {
                            logViewIsPinnedToBottom = true
                            jumpToLatestRequestID += 1
                        } label: {
                            Label("Jump to Bottom", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(.borderless)
                        .help("Jump to the bottom of the displayed logs")
                    }

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
                    formatsJSONLines: formatsJSONLines,
                    isPinnedToBottom: $logViewIsPinnedToBottom,
                    jumpToLatestRequestID: jumpToLatestRequestID,
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

                Toggle("JSON", isOn: $formatsJSONLines)
                    .toggleStyle(.checkbox)
                    .help("Safely pretty-print JSON log lines")
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

                HStack(spacing: 6) {
                    Text("Since")
                        .foregroundStyle(.secondary)

                    Picker("Since", selection: $sinceSelection) {
                        ForEach(LogSinceSelection.allCases) { selection in
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
        let timeScope = followsLogs ? "" : " - \(sinceSelection.subtitle)"
        if let containerName = selectedContainerForRequest {
            return "\(namespace) - \(containerName) - \(scope) - \(mode)\(timeScope)"
        }

        return "\(namespace) - \(scope) - \(mode)\(timeScope)"
    }

    private var activeSinceSeconds: Int? {
        followsLogs ? nil : sinceSelection.seconds
    }

    private var currentLogState: PodLogLoadState {
        appModel.podLogState(
            for: row,
            containerName: selectedContainerForRequest,
            timestamps: showsTimestamps,
            previous: showsPreviousLogs,
            tailLines: tailSelection.lineCount,
            sinceSeconds: activeSinceSeconds,
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
            sinceSeconds: activeSinceSeconds,
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
            sinceSeconds: activeSinceSeconds,
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
        .displayLines(formatsJSONLines: formatsJSONLines)
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
                tailLines: nil,
                sinceSeconds: activeSinceSeconds
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

private enum LogSinceSelection: String, CaseIterable, Identifiable {
    case any
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    case sixHours

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .any:
            "Any"
        case .fiveMinutes:
            "5m"
        case .fifteenMinutes:
            "15m"
        case .oneHour:
            "1h"
        case .sixHours:
            "6h"
        }
    }

    var subtitle: String {
        switch self {
        case .any:
            "any time"
        case .fiveMinutes:
            "last 5m"
        case .fifteenMinutes:
            "last 15m"
        case .oneHour:
            "last 1h"
        case .sixHours:
            "last 6h"
        }
    }

    var seconds: Int? {
        switch self {
        case .any:
            nil
        case .fiveMinutes:
            5 * 60
        case .fifteenMinutes:
            15 * 60
        case .oneHour:
            60 * 60
        case .sixHours:
            6 * 60 * 60
        }
    }
}

private struct LogTextSurface: View {
    let text: String
    let searchText: String
    let filtersMatches: Bool
    let formatsJSONLines: Bool
    @Binding var isPinnedToBottom: Bool
    let jumpToLatestRequestID: Int
    let followsLogs: Bool

    private var displayedLines: [String] {
        Self.lines(in: text, searchText: searchText, filtersMatches: filtersMatches)
    }

    private var displayedText: String {
        displayedLines.displayLines(formatsJSONLines: formatsJSONLines).joined(separator: "\n")
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
                    formatsJSONLines: formatsJSONLines,
                    isPinnedToBottom: $isPinnedToBottom,
                    jumpToLatestRequestID: jumpToLatestRequestID,
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
    let formatsJSONLines: Bool
    @Binding var isPinnedToBottom: Bool
    let jumpToLatestRequestID: Int
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
        scrollView.contentView.postsBoundsChangedNotifications = true

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
        context.coordinator.startObserving(scrollView)
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasPinnedToBottom = context.coordinator.isPinnedToBottom?.wrappedValue ?? true
        let shouldFollow = followsLogs && wasPinnedToBottom
        if context.coordinator.text != text ||
            context.coordinator.searchText != needle ||
            context.coordinator.formatsJSONLines != formatsJSONLines {
            let preservedOrigin = scrollView.contentView.bounds.origin
            context.coordinator.beginIgnoringBoundsChanges()
            textView.textStorage?.setAttributedString(
                Self.attributedText(
                    text,
                    searchText: needle,
                    highlightsJSON: formatsJSONLines
                )
            )
            context.coordinator.text = text
            context.coordinator.searchText = needle
            context.coordinator.formatsJSONLines = formatsJSONLines
            context.coordinator.layoutTextViewIfNeeded()

            if shouldFollow {
                context.coordinator.scrollToBottom(in: scrollView)
            } else {
                context.coordinator.restoreScrollPosition(
                    in: scrollView,
                    to: preservedOrigin,
                    pinnedValue: false
                )
            }
        }

        if context.coordinator.jumpToLatestRequestID != jumpToLatestRequestID {
            context.coordinator.jumpToLatestRequestID = jumpToLatestRequestID
            context.coordinator.scrollToBottom(in: scrollView)
        }
    }

    private static func attributedText(
        _ text: String,
        searchText: String,
        highlightsJSON: Bool
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        let result = NSMutableAttributedString(string: text, attributes: attributes)

        if highlightsJSON {
            highlightJSONSyntax(in: result, text: text)
        }

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

    private static func highlightJSONSyntax(in result: NSMutableAttributedString, text: String) {
        applyRegex(
            #""(?:\\.|[^"\\])*""#,
            to: result,
            text: text,
            attributes: [.foregroundColor: NSColor.systemGreen]
        )
        applyRegex(
            #""(?:\\.|[^"\\])*"(?=\s*:)"#,
            to: result,
            text: text,
            attributes: [
                .foregroundColor: NSColor.controlAccentColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            ]
        )
        applyRegex(
            #"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,
            to: result,
            text: text,
            attributes: [.foregroundColor: NSColor.systemPurple]
        )
        applyRegex(
            #"\b(?:true|false|null)\b"#,
            to: result,
            text: text,
            attributes: [.foregroundColor: NSColor.systemOrange]
        )
    }

    private static func applyRegex(
        _ pattern: String,
        to result: NSMutableAttributedString,
        text: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let matchRange = match?.range else {
                return
            }

            result.addAttributes(attributes, range: matchRange)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var ignoresBoundsChanges = false
        var isPinnedToBottom: Binding<Bool>?
        var text = ""
        var searchText = ""
        var formatsJSONLines = false
        var jumpToLatestRequestID = 0

        func startObserving(_ scrollView: NSScrollView) {
            stopObserving()
            self.scrollView = scrollView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else {
                    return
                }
                guard !self.ignoresBoundsChanges else {
                    return
                }

                self.publishPinnedState(for: scrollView)
            }
        }

        func stopObserving() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
            scrollView = nil
        }

        func beginIgnoringBoundsChanges() {
            ignoresBoundsChanges = true
        }

        func scrollToBottom(in scrollView: NSScrollView) {
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else {
                    return
                }

                self.ignoresBoundsChanges = true
                self.layoutTextViewIfNeeded()
                self.scrollVerticallyToBottom(in: scrollView)
                self.publishPinnedState(for: scrollView, forcedValue: true)
                DispatchQueue.main.async { [weak self] in
                    self?.ignoresBoundsChanges = false
                }
            }
        }

        func restoreScrollPosition(in scrollView: NSScrollView, to origin: NSPoint, pinnedValue: Bool) {
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else {
                    return
                }

                self.ignoresBoundsChanges = true
                self.layoutTextViewIfNeeded()
                self.scroll(in: scrollView, to: origin)
                self.publishPinnedState(for: scrollView, forcedValue: pinnedValue)
                DispatchQueue.main.async { [weak self] in
                    self?.ignoresBoundsChanges = false
                }
            }
        }

        func layoutTextViewIfNeeded() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset
            let width = max(textView.enclosingScrollView?.contentSize.width ?? 1, ceil(usedRect.width + inset.width * 2 + 24))
            let height = max(textView.enclosingScrollView?.contentSize.height ?? 1, ceil(usedRect.height + inset.height * 2 + 24))
            textView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        }

        private func scrollVerticallyToBottom(in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else {
                return
            }

            let clipView = scrollView.contentView
            let visibleBounds = clipView.bounds
            let maxX = max(0, documentView.bounds.width - visibleBounds.width)
            let maxY = max(0, documentView.bounds.height - visibleBounds.height)
            let preservedX = min(max(0, visibleBounds.origin.x), maxX)
            scroll(in: scrollView, to: NSPoint(x: preservedX, y: maxY))
        }

        private func scroll(in scrollView: NSScrollView, to origin: NSPoint) {
            guard let documentView = scrollView.documentView else {
                return
            }

            let clipView = scrollView.contentView
            let visibleBounds = clipView.bounds
            let maxX = max(0, documentView.bounds.width - visibleBounds.width)
            let maxY = max(0, documentView.bounds.height - visibleBounds.height)
            let clampedOrigin = NSPoint(
                x: min(max(0, origin.x), maxX),
                y: min(max(0, origin.y), maxY)
            )
            clipView.scroll(to: clampedOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }

        func isScrolledNearBottom(in scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else {
                return true
            }

            let visibleMaxY = scrollView.contentView.bounds.maxY
            let documentHeight = documentView.bounds.height
            return documentHeight - visibleMaxY <= 36
        }

        private func publishPinnedState(for scrollView: NSScrollView, forcedValue: Bool? = nil) {
            let newValue = forcedValue ?? isScrolledNearBottom(in: scrollView)
            guard isPinnedToBottom?.wrappedValue != newValue else {
                return
            }

            isPinnedToBottom?.wrappedValue = newValue
        }
    }
}

private extension [String] {
    func displayLines(formatsJSONLines: Bool) -> [String] {
        formatsJSONLines ? LogJSONLFormatter.formattedLines(from: self) : self
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

private struct ResourceDetailContainersView: View {
    let summary: KubernetesResourceDetailSummary

    var body: some View {
        Group {
            if summary.containers.isEmpty {
                EmptyStateView(
                    title: "No Containers",
                    subtitle: "This resource does not expose pod container details.",
                    systemImage: "shippingbox"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(summary.containers) { container in
                            ResourceContainerDebugSection(container: container)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .accessibilityIdentifier("resource.detail.containers")
    }
}

private struct ResourceContainerDebugSection: View {
    let container: KubernetesContainerSummary

    var body: some View {
        SectionSurface(title: container.name, systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 14) {
                header

                ResourceKeyValueList(rows: identityRows)

                if let currentState = container.currentState {
                    ResourceContainerStateBlock(
                        title: "Current State",
                        state: currentState
                    )
                }

                if let lastState = container.lastState {
                    ResourceContainerStateBlock(
                        title: "Last State",
                        state: lastState
                    )
                }

                ResourceContainerDebugSubsection(title: "Resources") {
                    ResourceKeyValueList(rows: resourceRows, emptyValue: "No requests or limits")
                }

                ResourceContainerDebugSubsection(title: "Probes") {
                    if container.probes.isEmpty {
                        Text("No probes")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(container.probes.enumerated()), id: \.element.id) { index, probe in
                                ResourceContainerProbeRow(probe: probe)

                                if index < container.probes.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                ResourceContainerDebugSubsection(title: "Volume Mounts") {
                    if container.volumeMounts.isEmpty {
                        Text("No volume mounts")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(container.volumeMounts.enumerated()), id: \.element.id) { index, mount in
                                ResourceContainerVolumeMountRow(mount: mount)

                                if index < container.volumeMounts.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ResourceContainerStatePill(state: container.currentState, ready: container.ready)

            Text(container.kind.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)

            if let restartCount = container.restartCount {
                Text("\(restartCount) restarts")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(restartCount > 0 ? .orange : .secondary)
            }

            if let readyText {
                Text(readyText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(container.ready == false ? .red : .secondary)
            }
        }
    }

    private var identityRows: [(String, String)] {
        [
            ("Image", container.image ?? "-"),
            ("Pull Policy", container.imagePullPolicy ?? "-"),
            ("Image ID", container.imageID ?? "-"),
            ("Container ID", container.containerID ?? "-"),
            ("Started", boolText(container.started))
        ].filter { !$0.1.isEmpty }
    }

    private var resourceRows: [(String, String)] {
        resourceRows(title: "Request", values: container.resources.requests) +
            resourceRows(title: "Limit", values: container.resources.limits)
    }

    private var readyText: String? {
        guard let ready = container.ready else {
            return nil
        }

        return ready ? "Ready" : "Not ready"
    }

    private func resourceRows(title: String, values: [String: String]) -> [(String, String)] {
        values
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .map { ("\(title) \($0.key)", $0.value) }
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else {
            return "-"
        }

        return value ? "true" : "false"
    }
}

private struct ResourceContainerDebugSubsection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct ResourceContainerStateBlock: View {
    let title: String
    let state: KubernetesContainerStateSummary

    var body: some View {
        ResourceContainerDebugSubsection(title: title) {
            ResourceKeyValueList(rows: rows)
        }
    }

    private var rows: [(String, String)] {
        [
            ("State", state.title),
            ("Message", state.message ?? ""),
            ("Started At", state.startedAt ?? ""),
            ("Finished At", state.finishedAt ?? ""),
            ("Exit Code", state.exitCode.map(String.init) ?? ""),
            ("Signal", state.signal.map(String.init) ?? "")
        ].filter { !$0.1.isEmpty }
    }
}

private struct ResourceContainerStatePill: View {
    let state: KubernetesContainerStateSummary?
    let ready: Bool?

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var title: String {
        if let state {
            return state.title
        }

        if ready == true {
            return "Ready"
        }

        if ready == false {
            return "Not ready"
        }

        return "State unknown"
    }

    private var tint: Color {
        switch state?.kind {
        case .running:
            return .green
        case .waiting:
            return .orange
        case .terminated:
            return .red
        case nil:
            return ready == true ? .green : .secondary
        }
    }
}

private struct ResourceContainerProbeRow: View {
    let probe: KubernetesContainerProbeSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(probe.kind.title)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)

                Text(probe.handler ?? "Handler unavailable")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(width: 220, alignment: .leading)

            Text(timingDescription)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var timingDescription: String {
        [
            probe.initialDelaySeconds.map { "initial=\($0)s" },
            probe.periodSeconds.map { "period=\($0)s" },
            probe.timeoutSeconds.map { "timeout=\($0)s" },
            probe.successThreshold.map { "success=\($0)" },
            probe.failureThreshold.map { "failure=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct ResourceContainerVolumeMountRow: View {
    let mount: KubernetesContainerVolumeMountSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mount.mountPath)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)

                Text(mount.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(width: 220, alignment: .leading)

            Text(detailText)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var detailText: String {
        [
            mount.readOnly ? "read-only" : "read-write",
            mount.subPath.map { "subPath=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
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
    @State private var isConfirmingReveal = false

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
        .confirmationDialog(
            "Reveal Secret value?",
            isPresented: $isConfirmingReveal,
            titleVisibility: .visible
        ) {
            Button("Reveal Value", role: .destructive) {
                revealSecretValue()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The value will be visible on screen until you hide it or close this inspector.")
        }
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

        if appModel.secretRevealRequiresConfirmation {
            isConfirmingReveal = true
            return
        }

        revealSecretValue()
    }

    private func revealSecretValue() {
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
            Image(systemName: statusSystemImage)
                .foregroundStyle(statusTint)

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

    private var statusSystemImage: String {
        if container.currentState?.kind == .waiting || container.ready == false {
            return "exclamationmark.circle.fill"
        }

        if container.currentState?.kind == .terminated {
            return "xmark.circle.fill"
        }

        if container.ready == true || container.currentState?.kind == .running {
            return "checkmark.circle.fill"
        }

        return "circle.fill"
    }

    private var statusTint: Color {
        if container.currentState?.kind == .waiting || (container.restartCount ?? 0) > 0 {
            return .orange
        }

        if container.currentState?.kind == .terminated || container.ready == false {
            return .red
        }

        if container.ready == true || container.currentState?.kind == .running {
            return .green
        }

        return .secondary
    }
}

private struct ResourceOwnerSummaryRow: View {
    let owner: KubernetesOwnerReferenceSummary
    let namespace: String?
    let openOwner: (KubernetesOwnerReferenceSummary, String?) -> Void

    var body: some View {
        if ResourceNavigationItem.navigationItem(forOwnerKind: owner.kind) != nil {
            Button {
                openOwner(owner, namespace)
            } label: {
                rowContent(showsDisclosure: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(owner.kind) \(owner.name)")
            .accessibilityIdentifier("resource.detail.owner.open.\(owner.kind).\(owner.name)")
        } else {
            rowContent(showsDisclosure: false)
        }
    }

    private func rowContent(showsDisclosure: Bool) -> some View {
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

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ResourceRelatedPodsRow: View {
    let selector: KubernetesLabelSelectorSummary
    let namespace: String?
    let sourceTitle: String
    let openPods: (KubernetesLabelSelectorSummary, String?, String) -> Void

    var body: some View {
        Button {
            openPods(selector, namespace, sourceTitle)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Show matching Pods")
                        .font(.callout.weight(.semibold))

                    Text(selector.displayText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                if let namespace {
                    Text(namespace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Pods matching \(selector.displayText)")
        .accessibilityIdentifier("resource.detail.relatedPods.open")
    }
}

private struct ResourceOwnedRelationshipAction: Identifiable {
    var title: String
    var owner: KubernetesOwnerReferenceSummary
    var targetResource: ResourceNavigationItem

    var id: String {
        "\(targetResource.id)/\(owner.id)"
    }
}

private struct ResourceRelatedOwnedResourcesRow: View {
    let action: ResourceOwnedRelationshipAction
    let namespace: String?
    let sourceTitle: String
    let openOwnedResources: (KubernetesOwnerReferenceSummary, ResourceNavigationItem, String?, String) -> Void

    var body: some View {
        Button {
            openOwnedResources(action.owner, action.targetResource, namespace, sourceTitle)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.callout.weight(.semibold))

                    Text("\(action.owner.kind)/\(action.owner.name)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                if let namespace {
                    Text(namespace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(action.targetResource.title) owned by \(action.owner.kind) \(action.owner.name)")
        .accessibilityIdentifier("resource.detail.relatedOwnedResources.open.\(action.targetResource.id)")
    }
}

private struct ResourceRelatedNamedResourceRow: View {
    let title: String
    let resource: ResourceNavigationItem
    let name: String
    let detail: String
    let namespace: String?
    let sourceTitle: String
    let openNamedResource: (ResourceNavigationItem, String, String?, String) -> Void

    var body: some View {
        Button {
            openNamedResource(resource, name, namespace, sourceTitle)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrowshape.turn.up.right")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))

                    Text("\(name) · \(detail)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                if let namespace {
                    Text(namespace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(resource.title) named \(name)")
        .accessibilityIdentifier("resource.detail.relatedNamedResource.open.\(resource.id).\(name)")
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
