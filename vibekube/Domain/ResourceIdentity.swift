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

struct ResourceListLoadingProgress: Equatable {
    var query: ResourceListQuery
    var startedAt: Date
    var itemCount: Int
    var pageCount: Int
    var remainingItemCount: Int?

    init(
        query: ResourceListQuery,
        startedAt: Date = Date(),
        itemCount: Int = 0,
        pageCount: Int = 0,
        remainingItemCount: Int? = nil
    ) {
        self.query = query
        self.startedAt = startedAt
        self.itemCount = itemCount
        self.pageCount = pageCount
        self.remainingItemCount = remainingItemCount
    }
}

struct ResourceListPageProgress: Equatable {
    var itemCount: Int
    var pageCount: Int
    var remainingItemCount: Int?
}

struct ResourceWatchReconnectState: Equatable {
    var attempt: Int
    var nextRetryAt: Date
    var message: String?
}

struct ResourceWatchStaleState: Equatable {
    var endedAt: Date
    var message: String
}

struct ResourceWatchFailureState: Equatable {
    var failedAt: Date
    var message: String
}

enum ResourceWatchStatus: Equatable {
    case idle
    case starting(Date)
    case live(since: Date, lastEventAt: Date?)
    case reconnecting(ResourceWatchReconnectState)
    case stale(ResourceWatchStaleState)
    case failed(ResourceWatchFailureState)
}

enum ResourceListLoadState: Equatable {
    case idle
    case loading(ResourceListLoadingProgress)
    case loaded(ResourceListSnapshot)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

struct ResourceDetailQuery: Identifiable, Hashable {
    var contextID: ClusterSummary.ID
    var resource: KubernetesDiscoveredResource
    var namespace: String?
    var name: String

    var id: String {
        [
            contextID,
            resource.id,
            namespace ?? "",
            name
        ].joined(separator: "|")
    }
}

struct ResourceDetailSnapshot: Equatable {
    var query: ResourceDetailQuery
    var yaml: String
    var summary: KubernetesResourceDetailSummary
    var loadedAt: Date
}

enum ResourceDetailLoadState: Equatable {
    case idle
    case loading
    case loaded(ResourceDetailSnapshot)
    case failed(String)
}

struct ResourceEventsQuery: Identifiable, Hashable {
    var contextID: ClusterSummary.ID
    var eventsResource: KubernetesDiscoveredResource
    var namespace: String?
    var involvedKind: String
    var involvedName: String
    var involvedUID: String?

    var id: String {
        [
            contextID,
            eventsResource.id,
            namespace ?? "",
            involvedKind,
            involvedName,
            involvedUID ?? ""
        ].joined(separator: "|")
    }
}

struct ResourceEventsSnapshot: Equatable {
    var query: ResourceEventsQuery
    var events: [KubernetesResourceEventSummary]
    var resourceVersion: String?
    var loadedAt: Date
}

enum ResourceEventsLoadState: Equatable {
    case idle
    case loading
    case loaded(ResourceEventsSnapshot)
    case failed(String)
}

struct ResourceEnvSecretValueQuery: Identifiable, Hashable {
    var contextID: ClusterSummary.ID
    var namespace: String
    var secretName: String
    var key: String

    var id: String {
        [
            contextID,
            namespace,
            secretName,
            key
        ].joined(separator: "|")
    }
}

enum ResourceEnvSecretValueLoadState: Equatable {
    case idle
    case loading
    case loaded(String)
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
