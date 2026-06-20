import Foundation

struct KubernetesConnectionSnapshot: Equatable {
    var version: KubernetesVersion
    var discovery: KubernetesDiscoverySnapshot

    init(
        version: KubernetesVersion,
        discovery: KubernetesDiscoverySnapshot = .empty
    ) {
        self.version = version
        self.discovery = discovery
    }
}

protocol KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot
}

extension KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot {
        try await connect(contextName: contextName, kubeconfig: kubeconfig) { _ in }
    }
}

enum KubernetesConnectionProgress: Equatable {
    case resolvingExecCredential(command: String)
    case refreshingExecCredential(command: String)
    case contactingAPI
    case discoveringAPIs

    var connectionState: ConnectionState {
        switch self {
        case .resolvingExecCredential, .refreshingExecCredential:
            .authenticating
        case .contactingAPI, .discoveringAPIs:
            .connecting
        }
    }

    var message: String {
        switch self {
        case .resolvingExecCredential(let command):
            "Signing in with \(command)."
        case .refreshingExecCredential(let command):
            "Refreshing credentials with \(command)."
        case .contactingAPI:
            "Contacting Kubernetes API."
        case .discoveringAPIs:
            "Loading Kubernetes API discovery."
        }
    }
}

final class KubernetesConnectionService: KubernetesConnectionServicing {
    private let execCredentialProvider: KubernetesExecCredentialProviding

    init(execCredentialProvider: KubernetesExecCredentialProviding = DefaultKubernetesExecCredentialProvider()) {
        self.execCredentialProvider = execCredentialProvider
    }

    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        var configuration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
        let execRequest = try await resolveExecCredentialIfNeeded(configuration: &configuration, progress: progress)

        await progress(.contactingAPI)
        let client = try DefaultKubernetesAPIClient(configuration: configuration)

        do {
            return try await snapshot(using: client, progress: progress)
        } catch let error as KubernetesClientError where error.connectionState == .unauthorized {
            guard let execRequest else {
                throw error
            }

            execCredentialProvider.invalidate(execRequest)
            var retryConfiguration = try KubernetesClientConfiguration(contextName: contextName, kubeconfig: kubeconfig)
            _ = try await resolveExecCredentialIfNeeded(
                configuration: &retryConfiguration,
                progress: progress,
                isRefresh: true
            )
            await progress(.contactingAPI)
            let retryClient = try DefaultKubernetesAPIClient(configuration: retryConfiguration)
            return try await snapshot(using: retryClient, progress: progress)
        }
    }

    private func snapshot(
        using client: KubernetesAPIClient,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
        let version = try await client.version()
        await progress(.discoveringAPIs)
        let discovery = try await discoverySnapshot(using: client)
        return KubernetesConnectionSnapshot(version: version, discovery: discovery)
    }

    private func discoverySnapshot(using client: KubernetesAPIClient) async throws -> KubernetesDiscoverySnapshot {
        let coreVersions = try await client.apiVersions()
        let apiGroups = try await client.apiGroups()
        let groupVersions = orderedGroupVersions(
            coreVersions.versions + apiGroups.groups.flatMap { group in
                group.versions.map(\.groupVersion)
            }
        )

        var resourceLists: [KubernetesAPIResourceList] = []
        for groupVersion in groupVersions {
            try Task.checkCancellation()
            do {
                let resourceList = try await client.resources(groupVersion: groupVersion)
                resourceLists.append(resourceList)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        let namespaceDiscovery: KubernetesNamespaceDiscovery
        do {
            let namespaceList = try await client.namespaces()
            namespaceDiscovery = .loaded(namespaceList.summaries)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            namespaceDiscovery = .failed(error.localizedDescription)
        }

        return KubernetesDiscoverySnapshot(
            coreVersions: coreVersions.versions,
            groups: apiGroups.groups,
            resourceLists: resourceLists,
            namespaceDiscovery: namespaceDiscovery
        )
    }

    private func resolveExecCredentialIfNeeded(
        configuration: inout KubernetesClientConfiguration,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void,
        isRefresh: Bool = false
    ) async throws -> KubernetesExecCredentialRequest? {
        guard case .exec(let request) = configuration.credential else {
            return nil
        }

        if isRefresh {
            await progress(.refreshingExecCredential(command: request.commandDisplayName))
        } else {
            await progress(.resolvingExecCredential(command: request.commandDisplayName))
        }
        configuration.credential = try await execCredentialProvider.credential(for: request)
        return request
    }

    private func orderedGroupVersions(_ groupVersions: [String]) -> [String] {
        var seen: Set<String> = []
        return groupVersions.filter { groupVersion in
            seen.insert(groupVersion).inserted
        }
    }
}
