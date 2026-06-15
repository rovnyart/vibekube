import Foundation

struct ClusterSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var contextName: String
    var server: String
    var namespace: String
    var sourceName: String
    var isCurrentContext: Bool
    var authDescription: String
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
            sourceName: "~/.kube/config",
            isCurrentContext: true,
            authDescription: "Client certificate",
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
            sourceName: "~/.kube/config",
            isCurrentContext: false,
            authDescription: "Teleport exec auth (tsh)",
            connectionState: .disconnected,
            kubernetesVersion: nil,
            lastSeenAt: nil
        ),
        ClusterSummary(
            id: "production",
            name: "production",
            contextName: "production",
            server: "https://production.example.invalid",
            namespace: "default",
            sourceName: "~/.kube/config",
            isCurrentContext: false,
            authDescription: "Bearer token",
            connectionState: .disconnected,
            kubernetesVersion: nil,
            lastSeenAt: nil
        )
    ]
}
