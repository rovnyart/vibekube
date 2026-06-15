//
//  vibekubeTests.swift
//  vibekubeTests
//
//  Created by art on 27.05.2026.
//

import Foundation
import Testing
@testable import vibekube

struct vibekubeTests {

    @MainActor
    @Test func appModelSelectsFirstClusterByDefault() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.selectedClusterID == "kind-vibekube-dev")
        #expect(model.selectedResource == .dashboard)
    }

    @MainActor
    @Test func appModelConnectsAndDisconnectsSelectedCluster() {
        let model = AppModel(clusters: ClusterSummary.preview)

        model.connectSelectedCluster()
        #expect(model.selectedConnectionState == .connected)

        model.disconnectSelectedCluster()
        #expect(model.selectedConnectionState == .disconnected)
    }

    @MainActor
    @Test func appModelConnectsWithConnectionService() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        #expect(model.selectedConnectionState == .connecting)

        await Task.yield()

        #expect(model.selectedConnectionState == .connected)
        #expect(model.selectedCluster?.kubernetesVersion == "v1.30.0")
        #expect(model.selectedDiscovery?.resourceCount == 1)
        #expect(model.selectedNamespaceSelection == "vibekube-demo")
        #expect(model.namespaceSelectionOptions.contains(AppModel.allNamespacesSelection))
        #expect(model.connectionErrorMessage == nil)
    }

    @MainActor
    @Test func appModelMapsConnectionFailures() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: FailingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        await Task.yield()

        #expect(model.selectedConnectionState == .unauthorized)
        #expect(model.connectionErrorMessage == "Nope")
    }

    @MainActor
    @Test func appModelLoadsResourceListForSelectedResource() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        await Task.yield()

        model.selectResource(.pods)
        await Task.yield()

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
            Issue.record("Expected loaded resource list")
            return
        }

        #expect(snapshot.items.map(\.displayName) == ["web-0"])
        #expect(snapshot.query.namespaceSelection == "vibekube-demo")
    }

    @Test func resourceNavigationGroupsWorkloads() {
        #expect(ResourceNavigationItem.pods.section == .workloads)
        #expect(ResourceNavigationItem.deployments.section == .workloads)
        #expect(ResourceNavigationItem.services.section == .network)
    }

}

private struct SucceedingConnectionService: KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot {
        KubernetesConnectionSnapshot(
            version: KubernetesVersion(
                major: "1",
                minor: "30",
                gitVersion: "v1.30.0",
                gitCommit: nil,
                platform: nil
            ),
            discovery: KubernetesDiscoverySnapshot(
                coreVersions: ["v1"],
                groups: [],
                resourceLists: [
                    KubernetesAPIResourceList(
                        groupVersion: "v1",
                        resources: [
                            KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list"], shortNames: nil, categories: nil)
                        ]
                    )
                ],
                namespaceDiscovery: .loaded([
                    KubernetesNamespaceSummary(name: "default", phase: "Active"),
                    KubernetesNamespaceSummary(name: "vibekube-demo", phase: "Active")
                ])
            )
        )
    }
}

private struct SucceedingResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(
            KubernetesUnstructuredResourceList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "all")"
                      },
                      "status": {
                        "phase": "Running"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }
}

private struct FailingConnectionService: KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot {
        throw KubernetesClientError.unauthorized("Nope")
    }
}

private func kubeconfig() -> Kubeconfig {
    Kubeconfig(
        apiVersion: "v1",
        kind: "Config",
        clusters: [],
        contexts: [],
        users: [],
        currentContext: nil
    )
}
