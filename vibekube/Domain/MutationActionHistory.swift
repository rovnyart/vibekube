import Foundation

enum MutationActionKind: String, CaseIterable, Identifiable, Equatable {
    case scale
    case restart
    case delete
    case apply
    case createNamespace
    case createConfigMap
    case createSecret

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .scale:
            "Scale"
        case .restart:
            "Restart"
        case .delete:
            "Delete"
        case .apply:
            "Apply YAML"
        case .createNamespace:
            "Create Namespace"
        case .createConfigMap:
            "Create ConfigMap"
        case .createSecret:
            "Create Secret"
        }
    }

    var systemImage: String {
        switch self {
        case .scale:
            "arrow.up.and.down"
        case .restart:
            "arrow.triangle.2.circlepath"
        case .delete:
            "trash"
        case .apply:
            "doc.badge.gearshape"
        case .createNamespace:
            "folder.badge.plus"
        case .createConfigMap:
            "curlybraces.square"
        case .createSecret:
            "key"
        }
    }
}

enum MutationActionStatus: Equatable {
    case running
    case succeeded
    case failed(String)

    var title: String {
        switch self {
        case .running:
            "Running"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        }
    }

    var message: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }
}

struct MutationActionRecord: Identifiable, Equatable {
    var id: UUID
    var kind: MutationActionKind
    var contextID: ClusterSummary.ID
    var namespace: String?
    var resourceKind: String
    var resourceName: String
    var detail: String
    var startedAt: Date
    var finishedAt: Date?
    var status: MutationActionStatus

    var targetTitle: String {
        if let namespace, !namespace.isEmpty {
            "\(resourceKind)/\(resourceName) in \(namespace)"
        } else {
            "\(resourceKind)/\(resourceName)"
        }
    }
}

struct KubernetesManifestApplyPreview: Equatable {
    var contextID: ClusterSummary.ID
    var resource: KubernetesDiscoveredResource
    var namespace: String?
    var name: String
    var dryRunResource: KubernetesResourceDetail
    var diff: KubernetesYAMLDiff

    var targetTitle: String {
        if let namespace, !namespace.isEmpty {
            "\(resource.kind)/\(name) in \(namespace)"
        } else {
            "\(resource.kind)/\(name)"
        }
    }
}
