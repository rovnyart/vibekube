import Foundation

protocol KubernetesMutationServicing {
    func mutate(
        contextName: String,
        kubeconfig: Kubeconfig,
        request: KubernetesMutationRequest
    ) async throws -> KubernetesMutationResult
}

final class KubernetesMutationService: KubernetesMutationServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func mutate(
        contextName: String,
        kubeconfig: Kubeconfig,
        request: KubernetesMutationRequest
    ) async throws -> KubernetesMutationResult {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await client.mutate(request)
        } catch let error as KubernetesMutationError where error.isUnauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await retryClient.mutate(request)
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
