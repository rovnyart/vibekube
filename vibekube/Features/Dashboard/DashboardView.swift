import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                connectionMessage

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    MetricTile(title: "API Groups", value: discoveryValue(\.apiGroupCount), systemImage: "square.stack.3d.up", tint: .indigo)
                    MetricTile(title: "API Resources", value: discoveryValue(\.resourceCount), systemImage: "shippingbox", tint: .blue)
                    MetricTile(title: "Namespaces", value: namespaceCount, systemImage: "folder", tint: .teal)
                    MetricTile(title: "Cluster Scoped", value: discoveryValue(\.clusterScopedResourceCount), systemImage: "globe", tint: .orange)
                }

                SectionSurface(title: "Cluster Snapshot", systemImage: "chart.bar.xaxis") {
                    DashboardRows(
                        cluster: appModel.selectedCluster,
                        discovery: appModel.selectedDiscovery,
                        selectedNamespace: appModel.selectedNamespaceTitle,
                        namespaceAccessError: appModel.namespaceAccessErrorMessage
                    )
                }

                SectionSurface(title: "Recent Events", systemImage: "waveform.path.ecg") {
                    DashboardRecentEventsView(
                        state: appModel.resourceListState(for: .events),
                        canLoadEvents: canLoadEvents,
                        unavailableMessage: eventsUnavailableMessage
                    ) {
                        appModel.loadResourceList(for: .events, force: true)
                    }
                    .task(id: appModel.resourceListTaskID(for: .events)) {
                        appModel.loadResourceList(for: .events)
                    }
                    .accessibilityIdentifier("dashboard.recentEvents")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("dashboard.view")
    }

    private var canLoadEvents: Bool {
        appModel.selectedConnectionState == .connected &&
            ResourceNavigationItem.events.discoveredResource(in: appModel.selectedDiscovery) != nil
    }

    private var eventsUnavailableMessage: String {
        if appModel.selectedConnectionState != .connected {
            return "Connect to a cluster to load recent events."
        }

        return "The Events API was not discovered for this cluster."
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appModel.selectedCluster?.name ?? "No Cluster")
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)
                Text(appModel.selectedCluster?.contextName ?? "No context selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            StatusBadge(state: appModel.selectedConnectionState)
        }
    }

    private var namespaceCount: String {
        guard let discovery = appModel.selectedDiscovery else {
            return "-"
        }

        if discovery.namespaceDiscovery.errorMessage != nil {
            return "!"
        }

        return "\(discovery.namespaceDiscovery.items.count)"
    }

    private func discoveryValue(_ keyPath: KeyPath<KubernetesDiscoverySnapshot, Int>) -> String {
        guard let discovery = appModel.selectedDiscovery else {
            return "-"
        }

        return "\(discovery[keyPath: keyPath])"
    }

    @ViewBuilder
    private var connectionMessage: some View {
        if let message = appModel.connectionErrorMessage, !message.isEmpty {
            Label(message, systemImage: appModel.selectedConnectionState.systemImage)
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
                .accessibilityIdentifier("dashboard.connectionError")
        }
    }
}

private struct DashboardRecentEventsView: View {
    let state: ResourceListLoadState
    let canLoadEvents: Bool
    let unavailableMessage: String
    let reload: () -> Void

    var body: some View {
        switch state {
        case .idle:
            if canLoadEvents {
                ProgressView("Loading Events")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                EmptyStateView(
                    title: "No Events Loaded",
                    subtitle: unavailableMessage,
                    systemImage: "waveform.path.ecg"
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        case .loading:
            ProgressView("Loading Events")
                .frame(maxWidth: .infinity, minHeight: 120)
        case .loaded(let snapshot):
            loadedContent(snapshot)
        case .failed(let message):
            VStack(spacing: 12) {
                EmptyStateView(
                    title: "Could Not Load Events",
                    subtitle: message,
                    systemImage: "exclamationmark.triangle"
                )

                Button(action: reload) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder
    private func loadedContent(_ snapshot: ResourceListSnapshot) -> some View {
        let events = sortedEvents(snapshot.items)

        if events.isEmpty {
            EmptyStateView(
                title: "No Recent Events",
                subtitle: "Kubernetes has not reported events for this scope.",
                systemImage: "waveform.path.ecg"
            )
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(events.count) recent events")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Loaded \(snapshot.loadedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button(action: reload) {
                        Label("Refresh Events", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Events")
                }

                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(8).enumerated()), id: \.element.id) { index, event in
                        DashboardEventRow(event: event)

                        if index < min(events.count, 8) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func sortedEvents(_ events: [KubernetesUnstructuredResource]) -> [KubernetesUnstructuredResource] {
        events.sorted { lhs, rhs in
            switch (lhs.eventLastObservedDate, rhs.eventLastObservedDate) {
            case (.some(let lhsDate), .some(let rhsDate)):
                lhsDate > rhsDate
            case (.some, .none):
                true
            case (.none, .some):
                false
            case (.none, .none):
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }
    }
}

private struct DashboardEventRow: View {
    let event: KubernetesUnstructuredResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DashboardEventTypePill(type: event.type ?? "-")
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.reason ?? event.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .textSelection(.enabled)

                    if let count = event.eventCount, count > 1 {
                        Text("\(count)x")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Text(event.eventAgeDescription())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let message = event.eventMessage, !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    if let source = event.eventSourceDescription, !source.isEmpty {
                        Label(source, systemImage: "antenna.radiowaves.left.and.right")
                    }

                    if let involved = event.eventInvolvedObjectDescription, !involved.isEmpty {
                        Label(involved, systemImage: "scope")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            }
        }
        .padding(.vertical, 9)
    }
}

private struct DashboardEventTypePill: View {
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

private struct DashboardRows: View {
    let cluster: ClusterSummary?
    let discovery: KubernetesDiscoverySnapshot?
    let selectedNamespace: String
    let namespaceAccessError: String?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                Text("Context")
                    .foregroundStyle(.secondary)
                Text(cluster?.contextName ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Namespace")
                    .foregroundStyle(.secondary)
                Text(selectedNamespace)
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Source")
                    .foregroundStyle(.secondary)
                Text(cluster?.sourceName ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Auth")
                    .foregroundStyle(.secondary)
                Text(cluster?.authDescription ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Server")
                    .foregroundStyle(.secondary)
                Text(cluster?.server ?? "None")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Version")
                    .foregroundStyle(.secondary)
                Text(cluster?.kubernetesVersion ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("API Groups")
                    .foregroundStyle(.secondary)
                Text(discovery.map { "\($0.apiGroupCount)" } ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("API Resources")
                    .foregroundStyle(.secondary)
                Text(discovery.map { "\($0.resourceCount)" } ?? "Unknown")
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Namespace Access")
                    .foregroundStyle(.secondary)
                Text(namespaceAccessText)
                    .foregroundStyle(namespaceAccessError == nil ? Color.primary : Color.orange)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var namespaceAccessText: String {
        if let namespaceAccessError {
            return namespaceAccessError
        }

        return discovery == nil ? "Unknown" : "Loaded"
    }
}
