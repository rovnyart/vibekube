import Foundation

struct KubernetesConnectionSnapshot: Equatable {
    var version: KubernetesVersion
}

protocol KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot
}

final class KubernetesConnectionService: KubernetesConnectionServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)

        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            let version = try await client.version()
            return KubernetesConnectionSnapshot(version: version)
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            let version = try await retryClient.version()
            return KubernetesConnectionSnapshot(version: version)
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
