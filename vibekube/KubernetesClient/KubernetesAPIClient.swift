import Foundation

protocol KubernetesAPIClient {
    func version() async throws -> KubernetesVersion
    func apiVersions() async throws -> KubernetesAPIVersions
    func apiGroups() async throws -> KubernetesAPIGroupList
    func resources(groupVersion: String) async throws -> KubernetesAPIResourceList
    func namespaces() async throws -> KubernetesNamespaceList
    func resourceList(
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList
    func resourceWatch(
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?,
        fieldSelector: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error>
    func resourceDetail(
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail
    func resourceEvents(
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList
    func nodeMetrics() async throws -> KubernetesNodeMetricsList
    func podMetrics(namespace: String?) async throws -> KubernetesPodMetricsList
    func podLogs(
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String
    func podLogStream(
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error>
    func mutate(_ request: KubernetesMutationRequest) async throws -> KubernetesMutationResult
}

struct KubernetesVersion: Decodable, Equatable {
    var major: String
    var minor: String
    var gitVersion: String
    var gitCommit: String?
    var platform: String?
}

struct KubernetesStatus: Decodable, Equatable {
    var kind: String?
    var apiVersion: String?
    var status: String?
    var message: String?
    var reason: String?
    var details: KubernetesStatusDetails?
    var code: Int?

    var fieldCauses: [KubernetesStatusCause] {
        details?.causes ?? []
    }

    var retryAfterSeconds: Int? {
        details?.retryAfterSeconds
    }
}

struct KubernetesStatusDetails: Decodable, Equatable {
    var name: String?
    var group: String?
    var kind: String?
    var uid: String?
    var causes: [KubernetesStatusCause]?
    var retryAfterSeconds: Int?
}

struct KubernetesStatusCause: Decodable, Equatable {
    var reason: String?
    var message: String?
    var field: String?
}

enum KubernetesMutationVerb: String, Equatable {
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct KubernetesMutationRequest: Equatable {
    var verb: KubernetesMutationVerb
    var resource: KubernetesDiscoveredResource
    var namespace: String?
    var name: String?
    var body: Data?
    var contentType: String
    var dryRun: Bool
    var extraQueryItems: [URLQueryItem]

    init(
        verb: KubernetesMutationVerb,
        resource: KubernetesDiscoveredResource,
        namespace: String? = nil,
        name: String? = nil,
        body: Data? = nil,
        contentType: String = "application/json",
        dryRun: Bool = false,
        extraQueryItems: [URLQueryItem] = []
    ) {
        self.verb = verb
        self.resource = resource
        self.namespace = namespace
        self.name = name
        self.body = body
        self.contentType = contentType
        self.dryRun = dryRun
        self.extraQueryItems = extraQueryItems
    }

    var path: String {
        if let name, !name.isEmpty {
            return resource.itemPath(namespace: namespace, name: name)
        }
        return resource.listPath(namespace: namespace)
    }

    var queryItems: [URLQueryItem] {
        var items = extraQueryItems
        if dryRun {
            items.append(URLQueryItem(name: "dryRun", value: "All"))
        }
        return items
    }
}

struct KubernetesMutationResult: Equatable {
    var statusCode: Int
    var status: KubernetesStatus?
    var resource: KubernetesResourceDetail?
}

enum KubernetesMutationError: LocalizedError, Equatable {
    case status(KubernetesStatus, httpStatusCode: Int)
    case emptyResponse(Int)

    var status: KubernetesStatus? {
        switch self {
        case .status(let status, _):
            status
        case .emptyResponse:
            nil
        }
    }

    var httpStatusCode: Int {
        switch self {
        case .status(_, let httpStatusCode), .emptyResponse(let httpStatusCode):
            httpStatusCode
        }
    }

    var isUnauthorized: Bool {
        httpStatusCode == 401
    }

    var isForbidden: Bool {
        httpStatusCode == 403
    }

    var isNotFound: Bool {
        httpStatusCode == 404
    }

    var isConflict: Bool {
        httpStatusCode == 409
    }

    var isValidationFailure: Bool {
        httpStatusCode == 422 || status?.reason == "Invalid"
    }

    var retryAfterSeconds: Int? {
        status?.retryAfterSeconds
    }

    var fieldCauses: [KubernetesStatusCause] {
        status?.fieldCauses ?? []
    }

    var errorDescription: String? {
        switch self {
        case .status(let status, let httpStatusCode):
            var parts = ["Kubernetes mutation failed with HTTP \(httpStatusCode)."]
            if let reason = status.reason, !reason.isEmpty {
                parts.append(reason)
            }
            if let message = status.message, !message.isEmpty {
                parts.append(DiagnosticsRedactor.redactedText(message))
            }
            let causes = status.fieldCauses.compactMap { cause -> String? in
                guard let message = cause.message, !message.isEmpty else {
                    return nil
                }
                if let field = cause.field, !field.isEmpty {
                    return "\(field): \(DiagnosticsRedactor.redactedText(message))"
                }
                return DiagnosticsRedactor.redactedText(message)
            }
            if !causes.isEmpty {
                parts.append("Causes: \(causes.joined(separator: "; "))")
            }
            if let retryAfterSeconds = status.retryAfterSeconds {
                parts.append("Retry after \(retryAfterSeconds)s.")
            }
            return parts.joined(separator: " ")
        case .emptyResponse(let httpStatusCode):
            return "Kubernetes mutation failed with HTTP \(httpStatusCode)."
        }
    }
}
