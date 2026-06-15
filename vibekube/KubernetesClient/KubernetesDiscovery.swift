import Foundation

struct KubernetesDiscoverySnapshot: Equatable {
    var coreVersions: [String]
    var groups: [KubernetesAPIGroup]
    var resourceLists: [KubernetesAPIResourceList]
    var namespaceDiscovery: KubernetesNamespaceDiscovery

    static let empty = KubernetesDiscoverySnapshot(
        coreVersions: [],
        groups: [],
        resourceLists: [],
        namespaceDiscovery: .empty
    )

    var discoveredResources: [KubernetesDiscoveredResource] {
        resourceLists
            .flatMap { resourceList in
                resourceList.resources.map {
                    KubernetesDiscoveredResource(
                        groupVersion: resourceList.groupVersion,
                        resource: $0
                    )
                }
            }
            .filter { !$0.isSubresource }
            .sorted()
    }

    var resourceCount: Int {
        discoveredResources.count
    }

    var namespacedResourceCount: Int {
        discoveredResources.filter(\.namespaced).count
    }

    var clusterScopedResourceCount: Int {
        discoveredResources.filter { !$0.namespaced }.count
    }

    var apiGroupCount: Int {
        groups.count + (coreVersions.isEmpty ? 0 : 1)
    }
}

extension KubernetesDiscoverySnapshot {
    static let preview = KubernetesDiscoverySnapshot(
        coreVersions: ["v1"],
        groups: [
            KubernetesAPIGroup(
                name: "apps",
                versions: [
                    KubernetesGroupVersion(groupVersion: "apps/v1", version: "v1")
                ],
                preferredVersion: KubernetesGroupVersion(groupVersion: "apps/v1", version: "v1")
            ),
            KubernetesAPIGroup(
                name: "batch",
                versions: [
                    KubernetesGroupVersion(groupVersion: "batch/v1", version: "v1")
                ],
                preferredVersion: KubernetesGroupVersion(groupVersion: "batch/v1", version: "v1")
            )
        ],
        resourceLists: [
            KubernetesAPIResourceList(
                groupVersion: "v1",
                resources: [
                    KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list", "watch"], shortNames: ["po"], categories: ["all"]),
                    KubernetesAPIResource(name: "configmaps", singularName: "", namespaced: true, kind: "ConfigMap", verbs: ["get", "list", "watch"], shortNames: ["cm"], categories: nil),
                    KubernetesAPIResource(name: "secrets", singularName: "", namespaced: true, kind: "Secret", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil),
                    KubernetesAPIResource(name: "services", singularName: "", namespaced: true, kind: "Service", verbs: ["get", "list", "watch"], shortNames: ["svc"], categories: ["all"]),
                    KubernetesAPIResource(name: "events", singularName: "", namespaced: true, kind: "Event", verbs: ["get", "list", "watch"], shortNames: ["ev"], categories: nil),
                    KubernetesAPIResource(name: "namespaces", singularName: "", namespaced: false, kind: "Namespace", verbs: ["get", "list", "watch"], shortNames: ["ns"], categories: nil),
                    KubernetesAPIResource(name: "nodes", singularName: "", namespaced: false, kind: "Node", verbs: ["get", "list", "watch"], shortNames: ["no"], categories: nil)
                ]
            ),
            KubernetesAPIResourceList(
                groupVersion: "apps/v1",
                resources: [
                    KubernetesAPIResource(name: "deployments", singularName: "", namespaced: true, kind: "Deployment", verbs: ["get", "list", "watch"], shortNames: ["deploy"], categories: ["all"]),
                    KubernetesAPIResource(name: "replicasets", singularName: "", namespaced: true, kind: "ReplicaSet", verbs: ["get", "list", "watch"], shortNames: ["rs"], categories: ["all"]),
                    KubernetesAPIResource(name: "statefulsets", singularName: "", namespaced: true, kind: "StatefulSet", verbs: ["get", "list", "watch"], shortNames: ["sts"], categories: ["all"]),
                    KubernetesAPIResource(name: "daemonsets", singularName: "", namespaced: true, kind: "DaemonSet", verbs: ["get", "list", "watch"], shortNames: ["ds"], categories: ["all"])
                ]
            ),
            KubernetesAPIResourceList(
                groupVersion: "batch/v1",
                resources: [
                    KubernetesAPIResource(name: "jobs", singularName: "", namespaced: true, kind: "Job", verbs: ["get", "list", "watch"], shortNames: nil, categories: ["all"]),
                    KubernetesAPIResource(name: "cronjobs", singularName: "", namespaced: true, kind: "CronJob", verbs: ["get", "list", "watch"], shortNames: ["cj"], categories: ["all"])
                ]
            )
        ],
        namespaceDiscovery: .loaded([
            KubernetesNamespaceSummary(name: "default", phase: "Active"),
            KubernetesNamespaceSummary(name: "kube-system", phase: "Active"),
            KubernetesNamespaceSummary(name: "vibekube-demo", phase: "Active")
        ])
    )
}

struct KubernetesNamespaceDiscovery: Equatable {
    var items: [KubernetesNamespaceSummary]
    var errorMessage: String?

    static let empty = KubernetesNamespaceDiscovery(items: [], errorMessage: nil)

    static func loaded(_ items: [KubernetesNamespaceSummary]) -> KubernetesNamespaceDiscovery {
        KubernetesNamespaceDiscovery(items: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, errorMessage: nil)
    }

    static func failed(_ message: String) -> KubernetesNamespaceDiscovery {
        KubernetesNamespaceDiscovery(items: [], errorMessage: message)
    }
}

struct KubernetesAPIVersions: Decodable, Equatable {
    var versions: [String]
}

struct KubernetesAPIGroupList: Decodable, Equatable {
    var groups: [KubernetesAPIGroup]
}

struct KubernetesAPIGroup: Decodable, Equatable, Identifiable {
    var name: String
    var versions: [KubernetesGroupVersion]
    var preferredVersion: KubernetesGroupVersion?

    var id: String {
        name
    }
}

struct KubernetesGroupVersion: Decodable, Equatable {
    var groupVersion: String
    var version: String
}

struct KubernetesAPIResourceList: Decodable, Equatable {
    var groupVersion: String
    var resources: [KubernetesAPIResource]
}

struct KubernetesAPIResource: Decodable, Equatable, Hashable {
    var name: String
    var singularName: String
    var namespaced: Bool
    var kind: String
    var verbs: [String]
    var shortNames: [String]?
    var categories: [String]?
}

struct KubernetesDiscoveredResource: Identifiable, Equatable, Hashable, Comparable {
    var groupVersion: String
    var group: String
    var version: String
    var name: String
    var kind: String
    var namespaced: Bool
    var verbs: [String]
    var shortNames: [String]
    var categories: [String]

    var id: String {
        "\(groupVersion)/\(name)"
    }

    var isSubresource: Bool {
        name.contains("/")
    }

    var displayGroup: String {
        group.isEmpty ? "core" : group
    }

    var scopeTitle: String {
        namespaced ? "Namespaced" : "Cluster"
    }

    func listPath(namespace: String?) -> String {
        let basePath = group.isEmpty ? "/api/\(version)" : "/apis/\(group)/\(version)"
        if namespaced, let namespace, !namespace.isEmpty {
            return "\(basePath)/namespaces/\(namespace.kubernetesPathSegment)/\(name.kubernetesPathSegment)"
        }

        return "\(basePath)/\(name.kubernetesPathSegment)"
    }

    func itemPath(namespace: String?, name itemName: String) -> String {
        "\(listPath(namespace: namespace))/\(itemName.kubernetesPathSegment)"
    }

    init(groupVersion: String, resource: KubernetesAPIResource) {
        self.groupVersion = groupVersion
        let parts = groupVersion.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            self.group = parts[0]
            self.version = parts[1]
        } else {
            self.group = ""
            self.version = groupVersion
        }

        self.name = resource.name
        self.kind = resource.kind
        self.namespaced = resource.namespaced
        self.verbs = resource.verbs
        self.shortNames = resource.shortNames ?? []
        self.categories = resource.categories ?? []
    }

    static func < (lhs: KubernetesDiscoveredResource, rhs: KubernetesDiscoveredResource) -> Bool {
        if lhs.displayGroup != rhs.displayGroup {
            return lhs.displayGroup.localizedStandardCompare(rhs.displayGroup) == .orderedAscending
        }
        return lhs.kind.localizedStandardCompare(rhs.kind) == .orderedAscending
    }
}

private extension String {
    var kubernetesPathSegment: String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? self
    }
}

struct KubernetesNamespaceList: Decodable, Equatable {
    var items: [KubernetesNamespace]

    var summaries: [KubernetesNamespaceSummary] {
        items.compactMap { namespace in
            guard let name = namespace.metadata.name else {
                return nil
            }

            return KubernetesNamespaceSummary(
                name: name,
                phase: namespace.status?.phase ?? "Unknown"
            )
        }
    }
}

struct KubernetesNamespace: Decodable, Equatable {
    var metadata: KubernetesObjectMetadata
    var status: KubernetesNamespaceStatus?
}

struct KubernetesObjectMetadata: Decodable, Equatable, Hashable {
    var name: String?
    var namespace: String?
    var uid: String?
    var resourceVersion: String?
    var creationTimestamp: String?
    var deletionTimestamp: String?
    var labels: [String: String]?
}

struct KubernetesNamespaceStatus: Decodable, Equatable {
    var phase: String?
}

struct KubernetesNamespaceSummary: Identifiable, Hashable {
    var name: String
    var phase: String

    var id: String {
        name
    }
}
