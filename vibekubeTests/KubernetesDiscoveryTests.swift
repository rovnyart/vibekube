import Foundation
import Testing
@testable import vibekube

struct KubernetesDiscoveryTests {

    @Test func decodesAPIGroupList() throws {
        let groupList = try JSONDecoder().decode(
            KubernetesAPIGroupList.self,
            from: Data(
                """
                {
                  "kind": "APIGroupList",
                  "groups": [
                    {
                      "name": "apps",
                      "versions": [
                        { "groupVersion": "apps/v1", "version": "v1" }
                      ],
                      "preferredVersion": { "groupVersion": "apps/v1", "version": "v1" }
                    }
                  ]
                }
                """.utf8
            )
        )

        #expect(groupList.groups.first?.name == "apps")
        #expect(groupList.groups.first?.preferredVersion?.groupVersion == "apps/v1")
    }

    @Test func decodesResourceListAndFiltersSubresourcesFromSnapshot() throws {
        let resourceList = try JSONDecoder().decode(
            KubernetesAPIResourceList.self,
            from: Data(
                """
                {
                  "kind": "APIResourceList",
                  "groupVersion": "v1",
                  "resources": [
                    {
                      "name": "pods",
                      "singularName": "",
                      "namespaced": true,
                      "kind": "Pod",
                      "verbs": ["get", "list", "watch"],
                      "shortNames": ["po"],
                      "categories": ["all"]
                    },
                    {
                      "name": "pods/status",
                      "singularName": "",
                      "namespaced": true,
                      "kind": "Pod",
                      "verbs": ["get", "patch", "update"]
                    }
                  ]
                }
                """.utf8
            )
        )

        let snapshot = KubernetesDiscoverySnapshot(
            coreVersions: ["v1"],
            groups: [],
            resourceLists: [resourceList],
            namespaceDiscovery: .empty
        )

        #expect(resourceList.resources.count == 2)
        #expect(snapshot.discoveredResources.map(\.name) == ["pods"])
        #expect(snapshot.resourceCount == 1)
        #expect(snapshot.namespacedResourceCount == 1)
        #expect(snapshot.clusterScopedResourceCount == 0)
    }

    @Test func decodesNamespaceSummaries() throws {
        let namespaceList = try JSONDecoder().decode(
            KubernetesNamespaceList.self,
            from: Data(
                """
                {
                  "kind": "NamespaceList",
                  "items": [
                    {
                      "metadata": { "name": "default" },
                      "status": { "phase": "Active" }
                    },
                    {
                      "metadata": { "name": "kube-system" },
                      "status": { "phase": "Active" }
                    }
                  ]
                }
                """.utf8
            )
        )

        #expect(namespaceList.summaries == [
            KubernetesNamespaceSummary(name: "default", phase: "Active"),
            KubernetesNamespaceSummary(name: "kube-system", phase: "Active")
        ])
    }

    @Test func mapsNavigationItemsToDiscoveredResources() {
        let snapshot = KubernetesDiscoverySnapshot(
            coreVersions: ["v1"],
            groups: [
                KubernetesAPIGroup(
                    name: "apps",
                    versions: [KubernetesGroupVersion(groupVersion: "apps/v1", version: "v1")],
                    preferredVersion: KubernetesGroupVersion(groupVersion: "apps/v1", version: "v1")
                )
            ],
            resourceLists: [
                KubernetesAPIResourceList(
                    groupVersion: "v1",
                    resources: [
                        KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list"], shortNames: nil, categories: nil)
                    ]
                ),
                KubernetesAPIResourceList(
                    groupVersion: "apps/v1",
                    resources: [
                        KubernetesAPIResource(name: "deployments", singularName: "", namespaced: true, kind: "Deployment", verbs: ["get", "list"], shortNames: nil, categories: nil)
                    ]
                )
            ],
            namespaceDiscovery: .empty
        )

        #expect(ResourceNavigationItem.pods.discoveredResource(in: snapshot)?.kind == "Pod")
        #expect(ResourceNavigationItem.deployments.discoveredResource(in: snapshot)?.group == "apps")
        #expect(ResourceNavigationItem.services.discoveredResource(in: snapshot) == nil)
    }
}
