import Foundation

struct ClusterSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var contextName: String
    var server: String
    var namespace: String
    var connectionState: ConnectionState
    var kubernetesVersion: String?
    var lastSeenAt: Date?
}

extension ClusterSummary {
    static let preview: [ClusterSummary] = [
        ClusterSummary(
            id: "kind-vibekube-dev",
            name: "vibekube-dev",
            contextName: "kind-vibekube-dev",
            server: "https://127.0.0.1",
            namespace: "vibekube-demo",
            connectionState: .disconnected,
            kubernetesVersion: nil,
            lastSeenAt: nil
        ),
        ClusterSummary(
            id: "staging",
            name: "staging",
            contextName: "staging",
            server: "https://staging.example.invalid",
            namespace: "default",
            connectionState: .unsupportedAuth,
            kubernetesVersion: nil,
            lastSeenAt: nil
        ),
        ClusterSummary(
            id: "production",
            name: "production",
            contextName: "production",
            server: "https://production.example.invalid",
            namespace: "default",
            connectionState: .disconnected,
            kubernetesVersion: nil,
            lastSeenAt: nil
        )
    ]
}
