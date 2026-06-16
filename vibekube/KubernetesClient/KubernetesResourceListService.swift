import Foundation

protocol KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error>
}

extension KubernetesResourceListServicing {
    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

final class KubernetesResourceListService: KubernetesResourceListServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await client.resourceList(resource: resource, namespace: namespace)
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await retryClient.resourceList(resource: resource, namespace: namespace)
        }
    }

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [execCredentialProvider] in
                do {
                    var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
                    let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration)
                    let client = try DefaultKubernetesAPIClient(configuration: configuration)

                    do {
                        for try await event in client.resourceWatch(
                            resource: resource,
                            namespace: namespace,
                            resourceVersion: resourceVersion
                        ) {
                            continuation.yield(event)
                        }
                    } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
                        guard let execRequest else {
                            throw error
                        }

                        execCredentialProvider.invalidate(execRequest)
                        var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
                        _ = try await resolveExecCredentialIfNeeded(configuration: &retryConfiguration)
                        let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
                        for try await event in retryClient.resourceWatch(
                            resource: resource,
                            namespace: namespace,
                            resourceVersion: resourceVersion
                        ) {
                            continuation.yield(event)
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
