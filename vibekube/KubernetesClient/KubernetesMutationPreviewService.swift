import Foundation

protocol KubernetesMutationPreviewServicing {
    func previewExistingResource(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        proposedYAML: String
    ) async throws -> KubernetesMutationPreview
}

struct KubernetesMutationPreview: Equatable {
    var liveResource: KubernetesResourceDetail
    var proposedResource: KubernetesResourceDetail
    var dryRunResource: KubernetesResourceDetail
    var mutationRequest: KubernetesMutationRequest
    var diff: KubernetesYAMLDiff
}

struct KubernetesYAMLDiff: Equatable {
    var lines: [KubernetesYAMLDiffLine]

    var hasChanges: Bool {
        lines.contains { $0.kind != .context }
    }

    var unifiedText: String {
        lines.map(\.unifiedText).joined(separator: "\n")
    }

    static func between(old oldYAML: String, new newYAML: String) -> KubernetesYAMLDiff {
        let oldLines = normalizedLines(oldYAML)
        let newLines = normalizedLines(newYAML)
        var table = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1
        )

        if !oldLines.isEmpty, !newLines.isEmpty {
            for oldIndex in 1...oldLines.count {
                for newIndex in 1...newLines.count {
                    if oldLines[oldIndex - 1] == newLines[newIndex - 1] {
                        table[oldIndex][newIndex] = table[oldIndex - 1][newIndex - 1] + 1
                    } else {
                        table[oldIndex][newIndex] = max(
                            table[oldIndex - 1][newIndex],
                            table[oldIndex][newIndex - 1]
                        )
                    }
                }
            }
        }

        var oldIndex = oldLines.count
        var newIndex = newLines.count
        var reversed: [KubernetesYAMLDiffLine] = []

        while oldIndex > 0, newIndex > 0 {
            if oldLines[oldIndex - 1] == newLines[newIndex - 1] {
                reversed.append(.init(kind: .context, text: oldLines[oldIndex - 1]))
                oldIndex -= 1
                newIndex -= 1
            } else if table[oldIndex][newIndex - 1] >= table[oldIndex - 1][newIndex] {
                reversed.append(.init(kind: .addition, text: newLines[newIndex - 1]))
                newIndex -= 1
            } else {
                reversed.append(.init(kind: .removal, text: oldLines[oldIndex - 1]))
                oldIndex -= 1
            }
        }

        while oldIndex > 0 {
            reversed.append(.init(kind: .removal, text: oldLines[oldIndex - 1]))
            oldIndex -= 1
        }

        while newIndex > 0 {
            reversed.append(.init(kind: .addition, text: newLines[newIndex - 1]))
            newIndex -= 1
        }

        return KubernetesYAMLDiff(lines: reversed.reversed())
    }

    private static func normalizedLines(_ yaml: String) -> [String] {
        var lines = yaml.components(separatedBy: .newlines)
        while lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}

struct KubernetesYAMLDiffLine: Equatable {
    enum Kind: Equatable {
        case context
        case addition
        case removal
    }

    var kind: Kind
    var text: String

    var unifiedText: String {
        switch kind {
        case .context:
            "  \(text)"
        case .addition:
            "+ \(text)"
        case .removal:
            "- \(text)"
        }
    }
}

struct KubernetesMutationConflict: Equatable {
    var message: String
    var retryAfterSeconds: Int?
    var fieldCauses: [KubernetesStatusCause]
}

enum KubernetesMutationPreviewError: LocalizedError, Equatable {
    case invalidYAML(String)
    case missingField(String)
    case identityMismatch(field: String, expected: String, actual: String?)
    case namespaceNotAllowed(String)
    case dryRunReturnedStatus(KubernetesStatus)
    case dryRunReturnedEmpty
    case serverRejected(KubernetesMutationError)
    case conflict(KubernetesMutationConflict)

    var errorDescription: String? {
        switch self {
        case .invalidYAML(let message):
            "Invalid YAML: \(DiagnosticsRedactor.redactedText(message))"
        case .missingField(let field):
            "Manifest is missing required field `\(field)`."
        case .identityMismatch(let field, let expected, let actual):
            "Manifest `\(field)` is \(actual ?? "missing"), expected \(expected)."
        case .namespaceNotAllowed(let namespace):
            "Cluster-scoped resources must not set metadata.namespace; found \(namespace)."
        case .dryRunReturnedStatus(let status):
            DiagnosticsRedactor.redactedText(status.message ?? status.reason ?? "Dry-run returned Kubernetes Status.")
        case .dryRunReturnedEmpty:
            "Dry-run did not return a resource preview."
        case .serverRejected(let error):
            error.localizedDescription
        case .conflict(let conflict):
            conflict.message
        }
    }

    var fieldCauses: [KubernetesStatusCause] {
        switch self {
        case .serverRejected(let error):
            error.fieldCauses
        case .conflict(let conflict):
            conflict.fieldCauses
        case .invalidYAML, .missingField, .identityMismatch, .namespaceNotAllowed, .dryRunReturnedStatus, .dryRunReturnedEmpty:
            []
        }
    }
}

final class KubernetesMutationPreviewService: KubernetesMutationPreviewServicing {
    private let mutationService: KubernetesMutationServicing
    private let resourceDetailService: KubernetesResourceDetailServicing

    init(
        mutationService: KubernetesMutationServicing = KubernetesMutationService(),
        resourceDetailService: KubernetesResourceDetailServicing = KubernetesResourceDetailService()
    ) {
        self.mutationService = mutationService
        self.resourceDetailService = resourceDetailService
    }

    func previewExistingResource(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String,
        proposedYAML: String
    ) async throws -> KubernetesMutationPreview {
        let manifest = try KubernetesMutationManifest(yaml: proposedYAML)
        try manifest.validateExistingResourceTarget(resource: resource, namespace: namespace, name: name)

        let liveResource = try await resourceDetailService.resourceDetail(
            contextName: contextName,
            kubeconfig: kubeconfig,
            resource: resource,
            namespace: namespace,
            name: name
        )
        let mutationRequest = KubernetesMutationRequest(
            verb: .put,
            resource: resource,
            namespace: namespace,
            name: name,
            body: try JSONEncoder().encode(manifest.value),
            contentType: "application/json",
            dryRun: true
        )

        let dryRunResult: KubernetesMutationResult
        do {
            dryRunResult = try await mutationService.mutate(
                contextName: contextName,
                kubeconfig: kubeconfig,
                request: mutationRequest
            )
        } catch let error as KubernetesMutationError where error.isConflict {
            throw KubernetesMutationPreviewError.conflict(
                KubernetesMutationConflict(
                    message: error.localizedDescription,
                    retryAfterSeconds: error.retryAfterSeconds,
                    fieldCauses: error.fieldCauses
                )
            )
        } catch let error as KubernetesMutationError {
            throw KubernetesMutationPreviewError.serverRejected(error)
        }

        if let status = dryRunResult.status {
            throw KubernetesMutationPreviewError.dryRunReturnedStatus(status)
        }

        guard let dryRunResource = dryRunResult.resource else {
            throw KubernetesMutationPreviewError.dryRunReturnedEmpty
        }

        return KubernetesMutationPreview(
            liveResource: liveResource,
            proposedResource: manifest.detail,
            dryRunResource: dryRunResource,
            mutationRequest: mutationRequest,
            diff: KubernetesYAMLDiff.between(old: liveResource.yaml, new: dryRunResource.yaml)
        )
    }
}

private struct KubernetesMutationManifest {
    var value: KubernetesJSONValue

    init(yaml: String) throws {
        do {
            var parser = SimpleYAMLParser()
            value = try parser.parse(yaml).kubernetesJSONValue
        } catch {
            throw KubernetesMutationPreviewError.invalidYAML(error.localizedDescription)
        }

        guard case .object = value else {
            throw KubernetesMutationPreviewError.invalidYAML("manifest root must be a mapping")
        }
    }

    var detail: KubernetesResourceDetail {
        KubernetesResourceDetail(value: value)
    }

    var apiVersion: String? {
        value["apiVersion"]?.stringValue
    }

    var kind: String? {
        value["kind"]?.stringValue
    }

    var metadata: KubernetesJSONValue? {
        value["metadata"]
    }

    var name: String? {
        metadata?["name"]?.stringValue
    }

    var namespace: String? {
        metadata?["namespace"]?.stringValue
    }

    func validateExistingResourceTarget(
        resource: KubernetesDiscoveredResource,
        namespace expectedNamespace: String?,
        name expectedName: String
    ) throws {
        try require(apiVersion, field: "apiVersion")
        try require(kind, field: "kind")
        try require(metadata, field: "metadata")
        try require(name, field: "metadata.name")

        if apiVersion != resource.groupVersion {
            throw KubernetesMutationPreviewError.identityMismatch(
                field: "apiVersion",
                expected: resource.groupVersion,
                actual: apiVersion
            )
        }
        if kind != resource.kind {
            throw KubernetesMutationPreviewError.identityMismatch(
                field: "kind",
                expected: resource.kind,
                actual: kind
            )
        }
        if name != expectedName {
            throw KubernetesMutationPreviewError.identityMismatch(
                field: "metadata.name",
                expected: expectedName,
                actual: name
            )
        }

        if resource.namespaced {
            let expected = expectedNamespace ?? ""
            try require(namespace, field: "metadata.namespace")
            if namespace != expected {
                throw KubernetesMutationPreviewError.identityMismatch(
                    field: "metadata.namespace",
                    expected: expected,
                    actual: namespace
                )
            }
        } else if let namespace, !namespace.isEmpty {
            throw KubernetesMutationPreviewError.namespaceNotAllowed(namespace)
        }
    }

    private func require<T>(_ value: T?, field: String) throws {
        guard value != nil else {
            throw KubernetesMutationPreviewError.missingField(field)
        }
    }
}

private extension SimpleYAMLValue {
    var kubernetesJSONValue: KubernetesJSONValue {
        switch self {
        case .mapping(let mapping):
            return .object(mapping.mapValues(\.kubernetesJSONValue))
        case .sequence(let sequence):
            return .array(sequence.map(\.kubernetesJSONValue))
        case .scalar(let value):
            return Self.scalarJSONValue(value)
        case .null:
            return .null
        }
    }

    static func scalarJSONValue(_ value: String) -> KubernetesJSONValue {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        default:
            if let number = Double(trimmed), isPlainNumber(trimmed) {
                return .number(number)
            }
            return .string(value)
        }
    }

    static func isPlainNumber(_ value: String) -> Bool {
        value.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression) != nil
    }
}
