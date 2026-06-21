import Foundation

protocol KubernetesSafeMutationServicing {
    func scale(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        replicas: Int
    ) async throws -> KubernetesResourceDetail

    func restartRollout(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        restartedAt: Date
    ) async throws -> KubernetesResourceDetail

    func delete(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesStatus?

    func applyManifest(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        yaml: String,
        dryRun: Bool
    ) async throws -> KubernetesResourceDetail
}

enum KubernetesSafeMutationError: LocalizedError, Equatable {
    case unsupportedVerb(String)
    case invalidReplicaCount(Int)
    case returnedStatus(KubernetesStatus)
    case returnedEmpty
    case serverRejected(KubernetesMutationError)

    var errorDescription: String? {
        switch self {
        case .unsupportedVerb(let verb):
            "The Kubernetes API did not advertise `\(verb)` support for this resource."
        case .invalidReplicaCount(let count):
            "Replica count must be 0 or greater; got \(count)."
        case .returnedStatus(let status):
            DiagnosticsRedactor.redactedText(status.message ?? status.reason ?? "Mutation returned Kubernetes Status.")
        case .returnedEmpty:
            "Mutation completed without returning a resource."
        case .serverRejected(let error):
            error.localizedDescription
        }
    }
}

final class KubernetesSafeMutationService: KubernetesSafeMutationServicing {
    private let mutationService: KubernetesMutationServicing
    private let isoFormatter: ISO8601DateFormatter

    init(mutationService: KubernetesMutationServicing = KubernetesMutationService()) {
        self.mutationService = mutationService
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = isoFormatter
    }

    func scale(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        replicas: Int
    ) async throws -> KubernetesResourceDetail {
        guard resource.verbs.contains("patch") else {
            throw KubernetesSafeMutationError.unsupportedVerb("patch")
        }
        guard replicas >= 0 else {
            throw KubernetesSafeMutationError.invalidReplicaCount(replicas)
        }

        let request = KubernetesMutationRequest(
            verb: .patch,
            resource: resource,
            namespace: namespace,
            name: name,
            body: try JSONSerialization.data(withJSONObject: [
                "spec": ["replicas": replicas]
            ]),
            contentType: "application/merge-patch+json"
        )
        return try await resourceResult(contextName: contextName, kubeconfig: kubeconfig, request: request)
    }

    func restartRollout(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        restartedAt: Date
    ) async throws -> KubernetesResourceDetail {
        guard resource.verbs.contains("patch") else {
            throw KubernetesSafeMutationError.unsupportedVerb("patch")
        }

        let request = KubernetesMutationRequest(
            verb: .patch,
            resource: resource,
            namespace: namespace,
            name: name,
            body: try JSONSerialization.data(withJSONObject: [
                "spec": [
                    "template": [
                        "metadata": [
                            "annotations": [
                                "kubectl.kubernetes.io/restartedAt": isoFormatter.string(from: restartedAt)
                            ]
                        ]
                    ]
                ]
            ]),
            contentType: "application/merge-patch+json"
        )
        return try await resourceResult(contextName: contextName, kubeconfig: kubeconfig, request: request)
    }

    func delete(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesStatus? {
        guard resource.verbs.contains("delete") else {
            throw KubernetesSafeMutationError.unsupportedVerb("delete")
        }

        let request = KubernetesMutationRequest(
            verb: .delete,
            resource: resource,
            namespace: namespace,
            name: name
        )
        let result = try await mutate(contextName: contextName, kubeconfig: kubeconfig, request: request)
        return result.status
    }

    func applyManifest(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        yaml: String,
        dryRun: Bool
    ) async throws -> KubernetesResourceDetail {
        guard resource.verbs.contains("patch") else {
            throw KubernetesSafeMutationError.unsupportedVerb("patch")
        }

        let request = KubernetesMutationRequest(
            verb: .patch,
            resource: resource,
            namespace: namespace,
            name: name,
            body: Data(yaml.utf8),
            contentType: "application/apply-patch+yaml",
            dryRun: dryRun,
            extraQueryItems: [
                URLQueryItem(name: "fieldManager", value: "Vibekube"),
                URLQueryItem(name: "force", value: "false")
            ]
        )
        return try await resourceResult(contextName: contextName, kubeconfig: kubeconfig, request: request)
    }

    private func resourceResult(
        contextName: String,
        kubeconfig: Kubeconfig,
        request: KubernetesMutationRequest
    ) async throws -> KubernetesResourceDetail {
        let result = try await mutate(contextName: contextName, kubeconfig: kubeconfig, request: request)
        if let status = result.status {
            throw KubernetesSafeMutationError.returnedStatus(status)
        }
        guard let resource = result.resource else {
            throw KubernetesSafeMutationError.returnedEmpty
        }
        return resource
    }

    private func mutate(
        contextName: String,
        kubeconfig: Kubeconfig,
        request: KubernetesMutationRequest
    ) async throws -> KubernetesMutationResult {
        do {
            return try await mutationService.mutate(
                contextName: contextName,
                kubeconfig: kubeconfig,
                request: request
            )
        } catch let error as KubernetesMutationError {
            throw KubernetesSafeMutationError.serverRejected(error)
        }
    }
}
