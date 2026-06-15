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
    @Test func appModelRestoresRouteFromPreferences() {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            userPreferences: InMemoryUserPreferences(
                selectedContextID: "staging",
                selectedResourceID: ResourceNavigationItem.services.rawValue,
                selectedNamespaceByContextID: ["staging": "payments"]
            )
        )

        #expect(model.route == AppRoute(clusterID: "staging", resource: .services))
        #expect(model.selectedClusterID == "staging")
        #expect(model.selectedResource == .services)
        #expect(model.selectedNamespaceSelection == "payments")
    }

    @MainActor
    @Test func appModelIgnoresInvalidRestoredRouteResource() {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            userPreferences: InMemoryUserPreferences(
                selectedContextID: "missing",
                selectedResourceID: "not-a-resource"
            )
        )

        #expect(model.selectedClusterID == "kind-vibekube-dev")
        #expect(model.selectedResource == .dashboard)
    }

    @MainActor
    @Test func appModelResetsToDashboardWhenClusterChanges() {
        let model = AppModel(clusters: ClusterSummary.preview)

        model.selectResource(.pods)
        model.selectCluster(id: "staging")

        #expect(model.route == AppRoute(clusterID: "staging", resource: .dashboard))
    }

    @MainActor
    @Test func appModelRequestsSearchFocusForCommands() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.searchFocusRequestID == 0)
        model.focusSearchField()

        #expect(model.searchFocusRequestID == 1)
    }

    @MainActor
    @Test func appModelBuildsCopyableRouteIdentity() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        await Task.yield()
        model.selectResource(.pods)

        let identity = model.selectedRouteIdentityText ?? ""
        #expect(identity.contains("Context: kind-vibekube-dev"))
        #expect(identity.contains("Route: Pods"))
        #expect(identity.contains("API: v1/pods"))
        #expect(identity.contains("Namespace: All Namespaces"))
    }

    @MainActor
    @Test func appModelOnlyOpensLogsForConnectedWorkloadRoutes() {
        let model = AppModel(clusters: ClusterSummary.preview)

        model.selectResource(.pods)
        #expect(model.canOpenLogsForSelectedRoute == false)

        model.connectSelectedCluster()
        #expect(model.canOpenLogsForSelectedRoute == true)

        model.openLogsForSelectedRoute()
        #expect(model.selectedResource == .logs)

        model.selectResource(.services)
        #expect(model.canOpenLogsForSelectedRoute == false)
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
        #expect(model.selectedDiscovery?.resourceCount == 3)
        #expect(model.selectedNamespaceSelection == AppModel.allNamespacesSelection)
        #expect(model.selectedNamespaceTitle == "All Namespaces")
        #expect(model.namespaceSelectionOptions.contains(AppModel.allNamespacesSelection))
        #expect(model.namespaceSelectionOptions.contains("vibekube-demo"))
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
        #expect(snapshot.items.first?.displayNamespace == "vibekube-demo")
        #expect(snapshot.query.namespaceSelection == AppModel.allNamespacesSelection)
    }

    @MainActor
    @Test func appModelLoadsDashboardResourceListsTogether() async throws {
        let recorder = DashboardResourceListRecorder()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: DashboardConnectionService(),
            resourceListService: DashboardResourceListService(recorder: recorder),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()

        for _ in 0..<20 {
            if await recorder.count == AppModel.dashboardResourceItems.count {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let requestedNames = await recorder.resourceNames()
        let expectedNames = Set(AppModel.dashboardResourceItems.map { dashboardAPIResource(for: $0).name })
        #expect(Set(requestedNames) == expectedNames)

        for item in AppModel.dashboardResourceItems {
            guard case .loaded = model.resourceListState(for: item) else {
                Issue.record("Expected \(item.title) to be loaded")
                continue
            }
        }
    }

    @MainActor
    @Test func appModelLoadsResourceDetailForSelectedRow() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            resourceDetailService: SucceedingResourceDetailService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        await Task.yield()

        model.selectResource(.pods)
        await Task.yield()

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods),
              let row = snapshot.items.first else {
            Issue.record("Expected loaded resource row")
            return
        }

        model.loadResourceDetail(for: .pods, row: row)
        for _ in 0..<3 {
            await Task.yield()
        }

        guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: row) else {
            Issue.record("Expected loaded resource detail")
            return
        }

        #expect(detail.query.name == "web-0")
        #expect(detail.query.namespace == "vibekube-demo")
        #expect(detail.yaml.contains("kind: Pod"))
        #expect(detail.yaml.contains("name: web-0"))
        #expect(detail.yaml.contains("namespace: vibekube-demo"))
    }

    @MainActor
    @Test func appModelLoadsResourceEventsForSelectedDetail() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            resourceDetailService: SucceedingResourceDetailService(),
            resourceEventService: SucceedingResourceEventService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        await Task.yield()

        model.selectResource(.pods)
        await Task.yield()

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let row = listSnapshot.items.first else {
            Issue.record("Expected loaded resource row")
            return
        }

        model.loadResourceDetail(for: .pods, row: row)
        for _ in 0..<3 {
            await Task.yield()
        }

        guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: row) else {
            Issue.record("Expected loaded resource detail")
            return
        }

        model.loadResourceEvents(for: detail)
        for _ in 0..<3 {
            await Task.yield()
        }

        guard case .loaded(let events) = model.resourceEventsState(for: detail) else {
            Issue.record("Expected loaded resource events")
            return
        }

        #expect(events.query.involvedName == "web-0")
        #expect(events.query.involvedUID == "pod-uid")
        #expect(events.events.map(\.reason) == ["Pulled"])
    }

    @MainActor
    @Test func appModelRevealsEnvSecretValue() async {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceDetailService: SucceedingResourceDetailService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        await Task.yield()

        model.revealEnvSecretValue(
            namespace: "vibekube-demo",
            secretName: "web-secrets",
            key: "db-password"
        )
        for _ in 0..<3 {
            await Task.yield()
        }

        guard case .loaded(let value) = model.envSecretValueState(
            namespace: "vibekube-demo",
            secretName: "web-secrets",
            key: "db-password"
        ) else {
            Issue.record("Expected revealed secret env value")
            return
        }

        #expect(value == "test-password")
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
                            KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "secrets", singularName: "", namespaced: true, kind: "Secret", verbs: ["get"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "events", singularName: "", namespaced: true, kind: "Event", verbs: ["list"], shortNames: nil, categories: nil)
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

private struct DashboardConnectionService: KubernetesConnectionServicing {
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
                        resources: AppModel.dashboardResourceItems
                            .map(dashboardAPIResource(for:))
                            .filter { resource in
                                ["nodes", "pods", "persistentvolumes", "persistentvolumeclaims", "events"].contains(resource.name)
                            }
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "apps/v1",
                        resources: AppModel.dashboardResourceItems
                            .map(dashboardAPIResource(for:))
                            .filter { resource in
                                ["deployments", "statefulsets", "daemonsets"].contains(resource.name)
                            }
                    ),
                    KubernetesAPIResourceList(
                        groupVersion: "batch/v1",
                        resources: AppModel.dashboardResourceItems
                            .map(dashboardAPIResource(for:))
                            .filter { resource in
                                ["jobs", "cronjobs"].contains(resource.name)
                            }
                    )
                ],
                namespaceDiscovery: .loaded([
                    KubernetesNamespaceSummary(name: "default", phase: "Active")
                ])
            )
        )
    }
}

private actor DashboardResourceListRecorder {
    private var names: [String] = []

    var count: Int {
        names.count
    }

    func record(_ name: String) {
        names.append(name)
    }

    func resourceNames() -> [String] {
        names
    }
}

private struct DashboardResourceListService: KubernetesResourceListServicing {
    let recorder: DashboardResourceListRecorder

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try await Task.sleep(nanoseconds: 2_000_000)
        try Task.checkCancellation()
        await recorder.record(resource.name)

        return KubernetesUnstructuredResourceList(
            apiVersion: resource.groupVersion,
            kind: "\(resource.kind)List",
            metadata: nil,
            items: []
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
                        "namespace": "\(namespace ?? "vibekube-demo")"
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

private struct SucceedingResourceDetailService: KubernetesResourceDetailServicing {
    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        if resource.name == "secrets" {
            return try JSONDecoder().decode(
                KubernetesResourceDetail.self,
                from: Data(
                    """
                    {
                      "apiVersion": "v1",
                      "kind": "Secret",
                      "metadata": {
                        "name": "\(name)",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "data": {
                        "db-password": "dGVzdC1wYXNzd29yZA=="
                      },
                      "type": "Opaque"
                    }
                    """.utf8
                )
            )
        }

        let namespaceLine = namespace.map { #""namespace": "\#($0)","# } ?? ""
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    \(namespaceLine)
                    "uid": "pod-uid",
                    "labels": {
                      "app": "web"
                    }
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
                """.utf8
            )
        )
    }
}

private struct SucceedingResourceEventService: KubernetesResourceEventServicing {
    func resourceEvents(
        contextName: String,
        kubeconfig: Kubeconfig,
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList {
        #expect(eventsResource.name == "events")
        #expect(namespace == "vibekube-demo")
        #expect(involvedKind == "Pod")
        #expect(involvedName == "web-0")
        #expect(involvedUID == "pod-uid")

        return try JSONDecoder().decode(
            KubernetesResourceEventList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Event",
                      "metadata": {
                        "name": "web-0.pulled",
                        "namespace": "vibekube-demo",
                        "uid": "event-pulled",
                        "creationTimestamp": "2026-06-15T10:01:00Z"
                      },
                      "type": "Normal",
                      "reason": "Pulled",
                      "message": "Container image is present.",
                      "count": 1,
                      "lastTimestamp": "2026-06-15T10:01:00Z",
                      "involvedObject": {
                        "kind": "Pod",
                        "name": "web-0",
                        "namespace": "vibekube-demo",
                        "uid": "pod-uid"
                      },
                      "source": {
                        "component": "kubelet"
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

private func dashboardAPIResource(for item: ResourceNavigationItem) -> KubernetesAPIResource {
    let definition: (name: String, kind: String, namespaced: Bool)
    switch item {
    case .nodes:
        definition = ("nodes", "Node", false)
    case .pods:
        definition = ("pods", "Pod", true)
    case .deployments:
        definition = ("deployments", "Deployment", true)
    case .statefulSets:
        definition = ("statefulsets", "StatefulSet", true)
    case .daemonSets:
        definition = ("daemonsets", "DaemonSet", true)
    case .jobs:
        definition = ("jobs", "Job", true)
    case .cronJobs:
        definition = ("cronjobs", "CronJob", true)
    case .persistentVolumes:
        definition = ("persistentvolumes", "PersistentVolume", false)
    case .persistentVolumeClaims:
        definition = ("persistentvolumeclaims", "PersistentVolumeClaim", true)
    case .events:
        definition = ("events", "Event", true)
    default:
        definition = (item.rawValue, item.title, true)
    }

    return KubernetesAPIResource(
        name: definition.name,
        singularName: "",
        namespaced: definition.namespaced,
        kind: definition.kind,
        verbs: ["get", "list"],
        shortNames: nil,
        categories: nil
    )
}
