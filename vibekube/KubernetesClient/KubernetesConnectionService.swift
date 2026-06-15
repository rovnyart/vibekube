import Foundation

struct KubernetesConnectionSnapshot: Equatable {
    var version: KubernetesVersion
}

protocol KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot
}

struct KubernetesConnectionService: KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot {
        let configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)
        let version = try await client.version()
        return KubernetesConnectionSnapshot(version: version)
    }
}
