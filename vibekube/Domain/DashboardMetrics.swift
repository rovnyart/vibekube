import Foundation

struct DashboardMetricsQuery: Identifiable, Hashable {
    static let allNamespacesSelection = "__vibekube_all_namespaces__"

    var contextID: ClusterSummary.ID
    var namespaceSelection: String

    var id: String {
        "\(contextID)|\(namespaceSelection)"
    }

    var isAllNamespaces: Bool {
        namespaceSelection == Self.allNamespacesSelection
    }
}

struct DashboardMetricsSnapshot: Equatable {
    var query: DashboardMetricsQuery
    var nodeMetrics: [KubernetesNodeMetrics]
    var podMetrics: [KubernetesPodMetrics]
    var loadedAt: Date
}

enum DashboardMetricsLoadState: Equatable {
    case idle
    case loading
    case loaded(DashboardMetricsSnapshot)
    case unavailable(String)
    case failed(String)
}

struct DashboardResourceUsageSummary: Equatable {
    var state: DashboardMetricsLoadState
    var cpuUsageMillicores: Double
    var cpuCapacityMillicores: Double?
    var memoryUsageBytes: Double
    var memoryCapacityBytes: Double?
    var nodeMetricsCount: Int
    var podMetricsCount: Int
    var usesClusterNodeMetrics: Bool
    var loadedAt: Date?

    static func make(
        state: DashboardMetricsLoadState,
        nodeItems: [KubernetesUnstructuredResource]?
    ) -> DashboardResourceUsageSummary {
        guard case .loaded(let snapshot) = state else {
            return DashboardResourceUsageSummary(
                state: state,
                cpuUsageMillicores: 0,
                cpuCapacityMillicores: Self.cpuCapacityMillicores(from: nodeItems),
                memoryUsageBytes: 0,
                memoryCapacityBytes: Self.memoryCapacityBytes(from: nodeItems),
                nodeMetricsCount: 0,
                podMetricsCount: 0,
                usesClusterNodeMetrics: true,
                loadedAt: nil
            )
        }

        let usesClusterNodeMetrics = snapshot.query.isAllNamespaces
        let cpuUsageMillicores = usesClusterNodeMetrics
            ? Self.cpuUsageMillicores(from: snapshot.nodeMetrics)
            : Self.cpuUsageMillicores(from: snapshot.podMetrics)
        let memoryUsageBytes = usesClusterNodeMetrics
            ? Self.memoryUsageBytes(from: snapshot.nodeMetrics)
            : Self.memoryUsageBytes(from: snapshot.podMetrics)

        return DashboardResourceUsageSummary(
            state: state,
            cpuUsageMillicores: cpuUsageMillicores,
            cpuCapacityMillicores: usesClusterNodeMetrics ? Self.cpuCapacityMillicores(from: nodeItems) : nil,
            memoryUsageBytes: memoryUsageBytes,
            memoryCapacityBytes: usesClusterNodeMetrics ? Self.memoryCapacityBytes(from: nodeItems) : nil,
            nodeMetricsCount: snapshot.nodeMetrics.count,
            podMetricsCount: snapshot.podMetrics.count,
            usesClusterNodeMetrics: usesClusterNodeMetrics,
            loadedAt: snapshot.loadedAt
        )
    }

    var isLoaded: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    var isLoading: Bool {
        state == .loading
    }

    var unavailableMessage: String? {
        switch state {
        case .unavailable(let message), .failed(let message):
            message
        case .idle:
            "Metrics have not loaded yet."
        case .loading, .loaded:
            nil
        }
    }

    var cpuUsageFraction: Double? {
        guard let cpuCapacityMillicores, cpuCapacityMillicores > 0 else {
            return nil
        }
        return min(1, cpuUsageMillicores / cpuCapacityMillicores)
    }

    var memoryUsageFraction: Double? {
        guard let memoryCapacityBytes, memoryCapacityBytes > 0 else {
            return nil
        }
        return min(1, memoryUsageBytes / memoryCapacityBytes)
    }

    private static func cpuCapacityMillicores(from nodes: [KubernetesUnstructuredResource]?) -> Double? {
        guard let nodes else {
            return nil
        }

        let values = nodes.compactMap(\.nodeAllocatableCPUMillicores)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
    }

    private static func memoryCapacityBytes(from nodes: [KubernetesUnstructuredResource]?) -> Double? {
        guard let nodes else {
            return nil
        }

        let values = nodes.compactMap(\.nodeAllocatableMemoryBytes)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
    }

    private static func cpuUsageMillicores(from nodes: [KubernetesNodeMetrics]) -> Double {
        nodes.reduce(0) { partialResult, item in
            partialResult + (item.usage.cpu?.cpuMillicores ?? 0)
        }
    }

    private static func memoryUsageBytes(from nodes: [KubernetesNodeMetrics]) -> Double {
        nodes.reduce(0) { partialResult, item in
            partialResult + (item.usage.memory?.memoryBytes ?? 0)
        }
    }

    private static func cpuUsageMillicores(from pods: [KubernetesPodMetrics]) -> Double {
        pods.flatMap(\.containers).reduce(0) { partialResult, container in
            partialResult + (container.usage.cpu?.cpuMillicores ?? 0)
        }
    }

    private static func memoryUsageBytes(from pods: [KubernetesPodMetrics]) -> Double {
        pods.flatMap(\.containers).reduce(0) { partialResult, container in
            partialResult + (container.usage.memory?.memoryBytes ?? 0)
        }
    }
}

private extension KubernetesUnstructuredResource {
    var nodeAllocatableCPUMillicores: Double? {
        nodeAllocatableQuantity("cpu")?.cpuMillicores ??
            nodeCapacityQuantity("cpu")?.cpuMillicores
    }

    var nodeAllocatableMemoryBytes: Double? {
        nodeAllocatableQuantity("memory")?.memoryBytes ??
            nodeCapacityQuantity("memory")?.memoryBytes
    }

    func nodeAllocatableQuantity(_ key: String) -> KubernetesMetricsQuantity? {
        guard let value = status?["allocatable"]?[key]?.stringValue else {
            return nil
        }
        return KubernetesMetricsQuantity(rawValue: value)
    }

    func nodeCapacityQuantity(_ key: String) -> KubernetesMetricsQuantity? {
        guard let value = status?["capacity"]?[key]?.stringValue else {
            return nil
        }
        return KubernetesMetricsQuantity(rawValue: value)
    }
}
