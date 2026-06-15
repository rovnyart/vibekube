import Foundation

protocol KubernetesResourceDetailServicing {
    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail
}

final class KubernetesResourceDetailService: KubernetesResourceDetailServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await client.resourceDetail(resource: resource, namespace: namespace, name: name)
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await retryClient.resourceDetail(resource: resource, namespace: namespace, name: name)
        }
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
