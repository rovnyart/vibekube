import Foundation

enum DashboardHealthStatus: String, Equatable, Comparable {
    case unknown
    case healthy
    case progressing
    case warning
    case failed

    static func < (lhs: DashboardHealthStatus, rhs: DashboardHealthStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var title: String {
        switch self {
        case .unknown:
            "Unknown"
        case .healthy:
            "Healthy"
        case .progressing:
            "Progressing"
        case .warning:
            "Warning"
        case .failed:
            "Failed"
        }
    }

    private var severity: Int {
        switch self {
        case .healthy:
            0
        case .unknown:
            1
        case .progressing:
            2
        case .warning:
            3
        case .failed:
            4
        }
    }
}

struct ClusterDashboardSnapshot: Equatable {
    var nodeHealth: NodeHealthSummary
    var podHealth: PodHealthSummary
    var workloadHealth: WorkloadHealthSummary
    var storageHealth: StorageHealthSummary
    var eventHealth: DashboardEventHealthSummary
    var resourceCounts: [ResourceNavigationItem: Int]
    var loadedAt: Date?

    var status: DashboardHealthStatus {
        let statuses = [
            nodeHealth.status,
            podHealth.status,
            workloadHealth.status,
            storageHealth.status,
            eventHealth.status
        ]

        let knownStatuses = statuses.filter { $0 != .unknown }
        if knownStatuses.isEmpty {
            return .unknown
        }

        return knownStatuses.max() ?? .unknown
    }

    func resourceCount(for item: ResourceNavigationItem) -> Int? {
        resourceCounts[item]
    }

    static func make(
        states: [ResourceNavigationItem: ResourceListLoadState]
    ) -> ClusterDashboardSnapshot {
        let loadedSnapshots = states.values.compactMap(\.snapshot)
        let workloadSnapshots = [
            states[.deployments]?.snapshot,
            states[.statefulSets]?.snapshot,
            states[.daemonSets]?.snapshot,
            states[.jobs]?.snapshot,
            states[.cronJobs]?.snapshot
        ].compactMap { $0 }

        return ClusterDashboardSnapshot(
            nodeHealth: NodeHealthSummary(items: states[.nodes]?.snapshot?.items),
            podHealth: PodHealthSummary(items: states[.pods]?.snapshot?.items),
            workloadHealth: WorkloadHealthSummary(
                items: workloadSnapshots.flatMap(\.items),
                isLoaded: !workloadSnapshots.isEmpty
            ),
            storageHealth: StorageHealthSummary(
                persistentVolumes: states[.persistentVolumes]?.snapshot?.items,
                persistentVolumeClaims: states[.persistentVolumeClaims]?.snapshot?.items
            ),
            eventHealth: DashboardEventHealthSummary(items: states[.events]?.snapshot?.items),
            resourceCounts: Dictionary(
                uniqueKeysWithValues: states.compactMap { item, state in
                    guard let snapshot = state.snapshot else {
                        return nil
                    }
                    return (item, snapshot.items.count)
                }
            ),
            loadedAt: loadedSnapshots.map(\.loadedAt).max()
        )
    }
}

struct NodeHealthSummary: Equatable {
    var isLoaded: Bool
    var total: Int
    var ready: Int
    var notReady: Int
    var unknown: Int

    init(items: [KubernetesUnstructuredResource]?) {
        guard let items else {
            self.isLoaded = false
            self.total = 0
            self.ready = 0
            self.notReady = 0
            self.unknown = 0
            return
        }

        self.isLoaded = true
        self.total = items.count
        self.ready = items.filter { $0.nodeReadyState == true }.count
        self.notReady = items.filter { $0.nodeReadyState == false }.count
        self.unknown = items.count - ready - notReady
    }

    var status: DashboardHealthStatus {
        guard isLoaded, total > 0 else {
            return .unknown
        }

        if notReady > 0 {
            return .failed
        }

        if unknown > 0 {
            return .warning
        }

        return .healthy
    }
}

struct PodHealthSummary: Equatable {
    var isLoaded: Bool
    var total: Int
    var running: Int
    var pending: Int
    var failed: Int
    var succeeded: Int
    var unknown: Int
    var restartCount: Int

    init(items: [KubernetesUnstructuredResource]?) {
        guard let items else {
            self.isLoaded = false
            self.total = 0
            self.running = 0
            self.pending = 0
            self.failed = 0
            self.succeeded = 0
            self.unknown = 0
            self.restartCount = 0
            return
        }

        self.isLoaded = true
        self.total = items.count
        self.running = items.filter { $0.podPhase == "running" }.count
        self.pending = items.filter { $0.podPhase == "pending" }.count
        self.failed = items.filter { $0.podPhase == "failed" }.count
        self.succeeded = items.filter { $0.podPhase == "succeeded" }.count
        self.unknown = items.count - running - pending - failed - succeeded
        self.restartCount = items.reduce(0) { $0 + $1.containerRestartCount }
    }

    var status: DashboardHealthStatus {
        guard isLoaded, total > 0 else {
            return .unknown
        }

        if failed > 0 {
            return .failed
        }

        if pending > 0 || restartCount > 0 || unknown > 0 {
            return .warning
        }

        return .healthy
    }
}

struct WorkloadHealthSummary: Equatable {
    var isLoaded: Bool
    var total: Int
    var ready: Int
    var progressing: Int
    var unavailable: Int

    init(items: [KubernetesUnstructuredResource], isLoaded: Bool) {
        self.isLoaded = isLoaded
        self.total = items.count
        self.ready = 0
        self.progressing = 0
        self.unavailable = 0

        for item in items {
            switch item.workloadReadiness {
            case .ready:
                ready += 1
            case .progressing:
                progressing += 1
            case .unavailable:
                unavailable += 1
            }
        }
    }

    var status: DashboardHealthStatus {
        guard isLoaded, total > 0 else {
            return .unknown
        }

        if unavailable > 0 {
            return .failed
        }

        if progressing > 0 {
            return .progressing
        }

        return .healthy
    }
}

struct StorageHealthSummary: Equatable {
    var isLoaded: Bool
    var total: Int
    var bound: Int
    var pending: Int
    var lost: Int

    init(
        persistentVolumes: [KubernetesUnstructuredResource]?,
        persistentVolumeClaims: [KubernetesUnstructuredResource]?
    ) {
        let items = (persistentVolumes ?? []) + (persistentVolumeClaims ?? [])
        self.isLoaded = persistentVolumes != nil || persistentVolumeClaims != nil
        self.total = items.count
        self.bound = items.filter { $0.storagePhase == "bound" || $0.storagePhase == "available" }.count
        self.pending = items.filter { $0.storagePhase == "pending" }.count
        self.lost = items.filter { $0.storagePhase == "lost" || $0.storagePhase == "failed" }.count
    }

    var status: DashboardHealthStatus {
        guard isLoaded, total > 0 else {
            return .unknown
        }

        if lost > 0 {
            return .failed
        }

        if pending > 0 {
            return .warning
        }

        return .healthy
    }
}

struct DashboardEventHealthSummary: Equatable {
    var isLoaded: Bool
    var total: Int
    var warnings: Int
    var topWarnings: [DashboardWarningSummary]

    init(items: [KubernetesUnstructuredResource]?) {
        guard let items else {
            self.isLoaded = false
            self.total = 0
            self.warnings = 0
            self.topWarnings = []
            return
        }

        let warningItems = items.filter(\.isWarningEvent)
        var counts: [DashboardWarningKey: Int] = [:]
        for item in warningItems {
            counts[DashboardWarningKey(item: item), default: 0] += item.eventCount ?? 1
        }

        self.isLoaded = true
        self.total = items.count
        self.warnings = warningItems.count
        self.topWarnings = counts
            .map { key, count in
                DashboardWarningSummary(
                    reason: key.reason,
                    source: key.source,
                    involvedObject: key.involvedObject,
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.reason.localizedStandardCompare(rhs.reason) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
    }

    var status: DashboardHealthStatus {
        guard isLoaded else {
            return .unknown
        }

        return warnings > 0 ? .warning : .healthy
    }
}

struct DashboardWarningSummary: Equatable, Identifiable {
    var reason: String
    var source: String
    var involvedObject: String
    var count: Int

    var id: String {
        "\(reason)|\(source)|\(involvedObject)"
    }
}

private struct DashboardWarningKey: Hashable {
    var reason: String
    var source: String
    var involvedObject: String

    init(item: KubernetesUnstructuredResource) {
        self.reason = item.reason ?? "Warning"
        self.source = item.eventSourceDescription ?? "-"
        self.involvedObject = item.eventInvolvedObjectDescription ?? "-"
    }
}

private enum WorkloadReadiness {
    case ready
    case progressing
    case unavailable
}

private extension ResourceListLoadState {
    var snapshot: ResourceListSnapshot? {
        if case .loaded(let snapshot) = self {
            return snapshot
        }

        return nil
    }
}

private extension KubernetesUnstructuredResource {
    var nodeReadyState: Bool? {
        guard displayKind == "Node" else {
            return nil
        }

        let readyCondition = status?["conditions"]?.arrayValue?
            .first { $0["type"]?.stringValue == "Ready" }
        return readyCondition?["status"]?.conditionStatusBool
    }

    var podPhase: String {
        status?["phase"]?.stringValue?.lowercased() ?? "unknown"
    }

    var containerRestartCount: Int {
        status?["containerStatuses"]?.arrayValue?.reduce(0) { partialResult, value in
            partialResult + (value["restartCount"]?.intValue ?? 0)
        } ?? 0
    }

    var storagePhase: String {
        status?["phase"]?.stringValue?.lowercased() ?? "unknown"
    }

    var isWarningEvent: Bool {
        type?.localizedCaseInsensitiveContains("warning") == true
    }

    var workloadReadiness: WorkloadReadiness {
        if displayKind == "Job" {
            return jobReadiness
        }

        guard let desiredReplicas else {
            return .ready
        }

        let readyReplicas = readyReplicas ?? 0
        if desiredReplicas == 0 {
            return .ready
        }

        if readyReplicas >= desiredReplicas {
            return .ready
        }

        return readyReplicas > 0 ? .progressing : .unavailable
    }

    var jobReadiness: WorkloadReadiness {
        if (status?["failed"]?.intValue ?? 0) > 0 {
            return .unavailable
        }

        let completions = spec?["completions"]?.intValue ?? 1
        let succeeded = status?["succeeded"]?.intValue ?? 0
        if succeeded >= completions {
            return .ready
        }

        return (status?["active"]?.intValue ?? 0) > 0 ? .progressing : .ready
    }

    var desiredReplicas: Int? {
        spec?["replicas"]?.intValue ??
            status?["desiredNumberScheduled"]?.intValue ??
            status?["replicas"]?.intValue
    }

    var readyReplicas: Int? {
        status?["readyReplicas"]?.intValue ??
            status?["availableReplicas"]?.intValue ??
            status?["numberReady"]?.intValue ??
            status?["currentNumberScheduled"]?.intValue
    }
}

private extension KubernetesJSONValue {
    var conditionStatusBool: Bool? {
        stringValue.flatMap { value in
            switch value.lowercased() {
            case "true":
                true
            case "false":
                false
            default:
                nil
            }
        }
    }
}
