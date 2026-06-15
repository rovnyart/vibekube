import Foundation

enum ResourceScope: String, Hashable {
    case namespaced
    case cluster

    var title: String {
        switch self {
        case .namespaced:
            "Namespaced"
        case .cluster:
            "Cluster"
        }
    }
}

struct ResourceIdentity: Identifiable, Hashable {
    var group: String
    var version: String
    var name: String
    var kind: String
    var scope: ResourceScope

    var id: String {
        "\(groupVersion)/\(name)"
    }

    var groupVersion: String {
        group.isEmpty ? version : "\(group)/\(version)"
    }
}

struct ResourceListQuery: Identifiable, Hashable {
    var contextID: ClusterSummary.ID
    var resource: KubernetesDiscoveredResource
    var namespaceSelection: String

    var id: String {
        "\(contextID)|\(resource.id)|\(namespaceSelection)"
    }
}

struct ResourceListSnapshot: Equatable {
    var query: ResourceListQuery
    var items: [KubernetesUnstructuredResource]
    var resourceVersion: String?
    var continueToken: String?
    var loadedAt: Date
}

enum ResourceListLoadState: Equatable {
    case idle
    case loading
    case loaded(ResourceListSnapshot)
    case failed(String)
}

extension KubernetesDiscoveredResource {
    var identity: ResourceIdentity {
        ResourceIdentity(
            group: group,
            version: version,
            name: name,
            kind: kind,
            scope: namespaced ? .namespaced : .cluster
        )
    }
}
