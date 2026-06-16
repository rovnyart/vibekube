import Foundation

protocol KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String
    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error>
}

final class KubernetesLogService: KubernetesLogServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await client.podLogs(namespace: namespace, podName: podName, options: options)
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await retryClient.podLogs(namespace: namespace, podName: podName, options: options)
        }
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [execCredentialProvider] in
                do {
                    var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
                    let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
                    let client = try DefaultKubernetesAPIClient(configuration: configuration)

                    do {
                        for try await chunk in client.podLogStream(namespace: namespace, podName: podName, options: options) {
                            continuation.yield(chunk)
                        }
                    } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
                        guard let execRequest else {
                            throw error
                        }

                        execCredentialProvider.invalidate(execRequest)
                        var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
                        _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
                        let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
                        for try await chunk in retryClient.podLogStream(namespace: namespace, podName: podName, options: options) {
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
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
