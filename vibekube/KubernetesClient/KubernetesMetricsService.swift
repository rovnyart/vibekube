import Foundation

protocol KubernetesMetricsServicing {
    func dashboardMetrics(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String?
    ) async throws -> KubernetesDashboardMetrics
}

final class KubernetesMetricsService: KubernetesMetricsServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func dashboardMetrics(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String?
    ) async throws -> KubernetesDashboardMetrics {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await metrics(using: client, namespace: namespace)
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await metrics(using: retryClient, namespace: namespace)
        }
    }

    private func metrics(
        using client: KubernetesAPIClient,
        namespace: String?
    ) async throws -> KubernetesDashboardMetrics {
        async let nodeMetrics = client.nodeMetrics()
        async let podMetrics = client.podMetrics(namespace: namespace)
        return try await KubernetesDashboardMetrics(
            nodeMetrics: nodeMetrics.items,
            podMetrics: podMetrics.items
        )
    }

    private func resolveExecCredentialIfNeeded(
        configuration: inout KubernetesClientConfiguration
    ) async throws -> KubernetesExecCredentialRequest? {
        guard case .exec(let request) = configuration.credential else {
            return nil
        }

        configuration.credential = try await execCredentialProvider.credential(for: request)
        return request
    }
}
