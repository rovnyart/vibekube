import Foundation

struct KubernetesMetricsQuantity: Decodable, Equatable, Hashable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    var cpuMillicores: Double? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("n") {
            return numericPrefix(value, dropping: 1).map { $0 / 1_000_000 }
        }
        if value.hasSuffix("u") {
            return numericPrefix(value, dropping: 1).map { $0 / 1_000 }
        }
        if value.hasSuffix("m") {
            return numericPrefix(value, dropping: 1)
        }
        return Double(value).map { $0 * 1_000 }
    }

    var memoryBytes: Double? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let binarySuffixes: [(String, Double)] = [
            ("Ki", pow(1024, 1)),
            ("Mi", pow(1024, 2)),
            ("Gi", pow(1024, 3)),
            ("Ti", pow(1024, 4)),
            ("Pi", pow(1024, 5)),
            ("Ei", pow(1024, 6))
        ]
        let decimalSuffixes: [(String, Double)] = [
            ("K", pow(1000, 1)),
            ("M", pow(1000, 2)),
            ("G", pow(1000, 3)),
            ("T", pow(1000, 4)),
            ("P", pow(1000, 5)),
            ("E", pow(1000, 6))
        ]

        for (suffix, multiplier) in binarySuffixes + decimalSuffixes where value.hasSuffix(suffix) {
            return numericPrefix(value, dropping: suffix.count).map { $0 * multiplier }
        }

        if value.hasSuffix("m") {
            return numericPrefix(value, dropping: 1).map { $0 / 1_000 }
        }

        return Double(value)
    }

    private func numericPrefix(_ value: String, dropping suffixLength: Int) -> Double? {
        Double(value.dropLast(suffixLength))
    }
}

struct KubernetesMetricsUsage: Decodable, Equatable {
    var cpu: KubernetesMetricsQuantity?
    var memory: KubernetesMetricsQuantity?
}

struct KubernetesNodeMetricsList: Decodable, Equatable {
    var items: [KubernetesNodeMetrics]
}

struct KubernetesNodeMetrics: Decodable, Equatable, Identifiable {
    var metadata: KubernetesObjectMetadata
    var timestamp: String?
    var window: String?
    var usage: KubernetesMetricsUsage

    var id: String {
        metadata.name ?? "unknown-node"
    }
}

struct KubernetesPodMetricsList: Decodable, Equatable {
    var items: [KubernetesPodMetrics]
}

struct KubernetesPodMetrics: Decodable, Equatable, Identifiable {
    var metadata: KubernetesObjectMetadata
    var timestamp: String?
    var window: String?
    var containers: [KubernetesContainerMetrics]

    var id: String {
        "\(metadata.namespace ?? "-")/\(metadata.name ?? "unknown-pod")"
    }
}

struct KubernetesContainerMetrics: Decodable, Equatable {
    var name: String
    var usage: KubernetesMetricsUsage
}

struct KubernetesDashboardMetrics: Equatable {
    var nodeMetrics: [KubernetesNodeMetrics]
    var podMetrics: [KubernetesPodMetrics]
}
