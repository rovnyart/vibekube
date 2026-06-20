import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    private let healthColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)
    ]

    var body: some View {
        let snapshot = appModel.selectedDashboardSnapshot
        let resourceUsage = appModel.selectedDashboardResourceUsageSummary

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                connectionMessage

                healthStrip(snapshot: snapshot)

                SectionSurface(title: "Resource Usage", systemImage: "chart.line.uptrend.xyaxis") {
                    DashboardResourceUsageView(summary: resourceUsage) {
                        appModel.loadDashboardMetrics(force: true)
                    }
                }

                SectionSurface(title: "Cluster Inventory", systemImage: "square.grid.3x3") {
                    DashboardResourceInventoryView(
                        snapshot: snapshot,
                        discovery: appModel.selectedDiscovery
                    )
                }

                SectionSurface(title: "Cluster Snapshot", systemImage: "chart.bar.xaxis") {
                    DashboardRows(
                        cluster: appModel.selectedCluster,
                        discovery: appModel.selectedDiscovery,
                        selectedNamespace: appModel.selectedNamespaceTitle,
                        namespaceAccessError: appModel.namespaceAccessErrorMessage
                    )
                }

                SectionSurface(title: "Pod Health", systemImage: "shippingbox") {
                    DashboardPodHealthView(summary: snapshot.podHealth)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: appModel.dashboardTaskID) {
            appModel.loadDashboardResources()
            appModel.loadDashboardMetrics()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("dashboard.view")
    }

    private func healthStrip(snapshot: ClusterDashboardSnapshot) -> some View {
        LazyVGrid(columns: healthColumns, alignment: .leading, spacing: 12) {
            DashboardHealthTile(
                title: "Cluster",
                value: snapshot.status.title,
                detail: clusterHealthDetail(snapshot),
                status: snapshot.status,
                systemImage: "heart.text.square"
            )

            DashboardHealthTile(
                title: "Nodes",
                value: nodeValue(snapshot),
                detail: nodeDetail(snapshot),
                status: snapshot.nodeHealth.status,
                systemImage: "server.rack"
            )

            DashboardHealthTile(
                title: "Pods",
                value: podValue(snapshot),
                detail: podDetail(snapshot),
                status: snapshot.podHealth.status,
                systemImage: "shippingbox"
            )
        }
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

            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(state: appModel.selectedConnectionState)

                Button {
                    appModel.loadDashboardResources(force: true)
                    appModel.loadDashboardMetrics(force: true)
                } label: {
                    Label("Refresh Dashboard", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(appModel.selectedConnectionState != .connected)
                .help("Refresh Dashboard")
            }
        }
    }

    private func clusterHealthDetail(_ snapshot: ClusterDashboardSnapshot) -> String {
        if let loadedAt = snapshot.loadedAt {
            return "Updated \(loadedAt.formatted(date: .omitted, time: .standard))"
        }

        return appModel.selectedConnectionState == .connected ? "Loading resources" : "Connect to load health"
    }

    private func nodeValue(_ snapshot: ClusterDashboardSnapshot) -> String {
        let summary = snapshot.nodeHealth
        return summary.isLoaded ? "\(summary.ready)/\(summary.total)" : "-"
    }

    private func nodeDetail(_ snapshot: ClusterDashboardSnapshot) -> String {
        let summary = snapshot.nodeHealth
        guard summary.isLoaded else {
            return "Not loaded"
        }

        if summary.notReady > 0 {
            return "\(summary.notReady) not ready"
        }

        if summary.unknown > 0 {
            return "\(summary.unknown) unknown"
        }

        return "Ready nodes"
    }

    private func podValue(_ snapshot: ClusterDashboardSnapshot) -> String {
        let summary = snapshot.podHealth
        return summary.isLoaded ? "\(summary.running)/\(summary.total)" : "-"
    }

    private func podDetail(_ snapshot: ClusterDashboardSnapshot) -> String {
        let summary = snapshot.podHealth
        guard summary.isLoaded else {
            return "Not loaded"
        }

        if summary.failed > 0 {
            return "\(summary.failed) failed"
        }

        if summary.pending > 0 {
            return "\(summary.pending) pending"
        }

        if summary.restartCount > 0 {
            return "\(summary.restartCount) restarts"
        }

        return "Running pods"
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
        } else if let message = appModel.connectionProgressMessage, !message.isEmpty {
            Label(message, systemImage: appModel.selectedConnectionState.systemImage)
                .font(.callout)
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
                .accessibilityIdentifier("dashboard.connectionProgress")
        }
    }
}

private struct DashboardHealthTile: View {
    let title: String
    let value: String
    let detail: String
    let status: DashboardHealthStatus
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(status.tint)

                Spacer()

                Label(status.title, systemImage: status.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .labelStyle(.iconOnly)
                    .help(status.title)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(minHeight: 112, alignment: .leading)
        .appSurface(strokeColor: status.tint.opacity(0.24))
    }
}

private struct DashboardResourceUsageView: View {
    let summary: DashboardResourceUsageSummary
    let reload: () -> Void

    var body: some View {
        switch summary.state {
        case .loading:
            ProgressView("Loading CPU and memory metrics")
                .frame(maxWidth: .infinity, minHeight: 130)
        case .loaded:
            loadedContent
        case .idle:
            unavailableContent("Metrics have not loaded yet.")
        case .unavailable(let message), .failed(let message):
            unavailableContent(message)
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                DashboardUsageGauge(
                    title: "CPU",
                    value: formatCPU(summary.cpuUsageMillicores),
                    detail: usageDetail(
                        fraction: summary.cpuUsageFraction,
                        capacity: summary.cpuCapacityMillicores.map(formatCPU)
                    ),
                    fraction: summary.cpuUsageFraction,
                    systemImage: "cpu",
                    tint: .blue
                )

                DashboardUsageGauge(
                    title: "Memory",
                    value: formatMemory(summary.memoryUsageBytes),
                    detail: usageDetail(
                        fraction: summary.memoryUsageFraction,
                        capacity: summary.memoryCapacityBytes.map(formatMemory)
                    ),
                    fraction: summary.memoryUsageFraction,
                    systemImage: "memorychip",
                    tint: .green
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(metricsSourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let loadedAt = summary.loadedAt {
                    Text("Loaded \(loadedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button(action: reload) {
                    Label("Refresh Metrics", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Refresh Metrics")
            }
        }
    }

    private func unavailableContent(_ message: String) -> some View {
        VStack(spacing: 10) {
            EmptyStateView(
                title: "Metrics Unavailable",
                subtitle: message,
                systemImage: "chart.line.uptrend.xyaxis"
            )

            Button(action: reload) {
                Label("Retry Metrics", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    private func usageDetail(fraction: Double?, capacity: String?) -> String {
        guard let fraction, let capacity else {
            return "Capacity unavailable"
        }

        return "\(Int((fraction * 100).rounded()))% of \(capacity)"
    }

    private var metricsSourceLabel: String {
        if summary.usesClusterNodeMetrics {
            return "\(summary.nodeMetricsCount) nodes and \(summary.podMetricsCount) pods reported metrics"
        }

        return "\(summary.podMetricsCount) pods reported metrics in selected namespace"
    }

    private func formatCPU(_ millicores: Double) -> String {
        if millicores >= 1_000 {
            return "\(formatDecimal(millicores / 1_000, digits: 1)) cores"
        }

        return "\(Int(millicores.rounded()))m"
    }

    private func formatMemory(_ bytes: Double) -> String {
        let gib = bytes / pow(1024, 3)
        if gib >= 1 {
            return "\(formatDecimal(gib, digits: 1)) GiB"
        }

        let mib = bytes / pow(1024, 2)
        return "\(Int(mib.rounded())) MiB"
    }

    private func formatDecimal(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct DashboardUsageGauge: View {
    let title: String
    let value: String
    let detail: String
    let fraction: Double?
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(fraction ?? 0))
                }
            }
            .frame(height: 8)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardResourceInventoryView: View {
    let snapshot: ClusterDashboardSnapshot
    let discovery: KubernetesDiscoverySnapshot?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            DashboardInventoryMetric(
                title: "API Groups",
                value: discoveryValue(\.apiGroupCount),
                systemImage: "square.stack.3d.up"
            )
            DashboardInventoryMetric(
                title: "API Resources",
                value: discoveryValue(\.resourceCount),
                systemImage: "shippingbox"
            )
            DashboardInventoryMetric(
                title: "Namespaces",
                value: namespaceCount,
                systemImage: "folder"
            )
            DashboardInventoryMetric(
                title: "Cluster Scoped",
                value: discoveryValue(\.clusterScopedResourceCount),
                systemImage: "globe"
            )
            DashboardInventoryMetric(
                title: "Nodes",
                value: resourceCount(.nodes),
                systemImage: "server.rack"
            )
            DashboardInventoryMetric(
                title: "Pods",
                value: resourceCount(.pods),
                systemImage: "shippingbox"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var namespaceCount: String {
        guard let discovery else {
            return "-"
        }

        if discovery.namespaceDiscovery.errorMessage != nil {
            return "!"
        }

        return "\(discovery.namespaceDiscovery.items.count)"
    }

    private func discoveryValue(_ keyPath: KeyPath<KubernetesDiscoverySnapshot, Int>) -> String {
        discovery.map { "\($0[keyPath: keyPath])" } ?? "-"
    }

    private func resourceCount(_ item: ResourceNavigationItem) -> String {
        snapshot.resourceCount(for: item).map(String.init) ?? "-"
    }
}

private struct DashboardInventoryMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardPodHealthView: View {
    let summary: PodHealthSummary

    var body: some View {
        if !summary.isLoaded {
            DashboardMutedState(text: "Pod health has not loaded yet.")
        } else if summary.total == 0 {
            DashboardMutedState(text: "No pods in this scope.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                DashboardPhaseBar(
                    segments: [
                        DashboardPhaseSegment(title: "Running", count: summary.running, tint: .green),
                        DashboardPhaseSegment(title: "Pending", count: summary.pending, tint: .orange),
                        DashboardPhaseSegment(title: "Failed", count: summary.failed, tint: .red),
                        DashboardPhaseSegment(title: "Succeeded", count: summary.succeeded, tint: .blue),
                        DashboardPhaseSegment(title: "Unknown", count: summary.unknown, tint: .secondary)
                    ]
                )

                DashboardSummaryRow(title: "Running", value: "\(summary.running)")
                DashboardSummaryRow(title: "Pending", value: "\(summary.pending)")
                DashboardSummaryRow(title: "Failed", value: "\(summary.failed)")
                DashboardSummaryRow(title: "Succeeded", value: "\(summary.succeeded)")
                DashboardSummaryRow(title: "Container Restarts", value: "\(summary.restartCount)")
            }
        }
    }
}

private struct DashboardWorkloadHealthView: View {
    let summary: WorkloadHealthSummary

    var body: some View {
        if !summary.isLoaded {
            DashboardMutedState(text: "Workload health has not loaded yet.")
        } else if summary.total == 0 {
            DashboardMutedState(text: "No workloads in this scope.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                DashboardSummaryRow(title: "Ready", value: "\(summary.ready)")
                DashboardSummaryRow(title: "Progressing", value: "\(summary.progressing)")
                DashboardSummaryRow(title: "Unavailable", value: "\(summary.unavailable)")

                Divider()

                Text("\(summary.ready) of \(summary.total) workloads are ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DashboardWarningsView: View {
    let summary: DashboardEventHealthSummary

    var body: some View {
        if !summary.isLoaded {
            DashboardMutedState(text: "Warning events have not loaded yet.")
        } else if summary.topWarnings.isEmpty {
            DashboardMutedState(text: "No warning events in the current event window.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(summary.topWarnings.prefix(6).enumerated()), id: \.element.id) { index, warning in
                    DashboardWarningRow(warning: warning)

                    if index < min(summary.topWarnings.count, 6) - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct DashboardWarningRow: View {
    let warning: DashboardWarningSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(warning.count)x")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(warning.reason)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                Text(warning.involvedObject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                if warning.source != "-" {
                    Text(warning.source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct DashboardSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct DashboardMutedState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
    }
}

private struct DashboardPhaseSegment: Identifiable {
    var title: String
    var count: Int
    var tint: Color

    var id: String {
        title
    }
}

private struct DashboardPhaseBar: View {
    let segments: [DashboardPhaseSegment]

    var body: some View {
        let visibleSegments = segments.filter { $0.count > 0 }
        let total = visibleSegments.reduce(0) { $0 + $1.count }

        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(visibleSegments) { segment in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(segment.tint)
                            .frame(width: segmentWidth(segment.count, total: total, availableWidth: proxy.size.width))
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                ForEach(visibleSegments) { segment in
                    Label("\(segment.title) \(segment.count)", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(segment.tint)
                        .lineLimit(1)
                }
            }
        }
    }

    private func segmentWidth(_ count: Int, total: Int, availableWidth: CGFloat) -> CGFloat {
        guard total > 0 else {
            return 0
        }

        return max(4, availableWidth * CGFloat(count) / CGFloat(total))
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
        case .loading(_):
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

private extension DashboardHealthStatus {
    var tint: Color {
        switch self {
        case .healthy:
            .green
        case .progressing:
            .blue
        case .warning:
            .orange
        case .failed:
            .red
        case .unknown:
            .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .healthy:
            "checkmark.circle.fill"
        case .progressing:
            "arrow.triangle.2.circlepath"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        case .unknown:
            "questionmark.circle"
        }
    }
}
