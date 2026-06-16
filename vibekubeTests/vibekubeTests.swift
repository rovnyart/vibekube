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
    @Test func appModelBuildsCopyableRouteIdentity() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)
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
    @Test func appModelConnectsWithConnectionService() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        #expect(model.selectedConnectionState == .connecting)

        try await waitForConnectionState(model, .connected)

        #expect(model.selectedConnectionState == .connected)
        #expect(model.selectedCluster?.kubernetesVersion == "v1.30.0")
        #expect(model.selectedDiscovery?.resourceCount == 4)
        #expect(model.selectedNamespaceSelection == AppModel.allNamespacesSelection)
        #expect(model.selectedNamespaceTitle == "All Namespaces")
        #expect(model.namespaceSelectionOptions.contains(AppModel.allNamespacesSelection))
        #expect(model.namespaceSelectionOptions.contains("vibekube-demo"))
        #expect(model.connectionErrorMessage == nil)
    }

    @MainActor
    @Test func appModelMapsConnectionFailures() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: FailingConnectionService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .unauthorized)

        #expect(model.selectedConnectionState == .unauthorized)
        #expect(model.connectionErrorMessage == "Nope")
    }

    @MainActor
    @Test func appModelLoadsResourceListForSelectedResource() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

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
    @Test func appModelKeepsDashboardLoadsWhenNavigatingAway() async throws {
        let recorder = DashboardResourceListRecorder()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: DashboardConnectionService(),
            resourceListService: DashboardResourceListService(
                recorder: recorder,
                delayNanoseconds: 50_000_000
            ),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        for _ in 0..<20 {
            if model.selectedConnectionState == .connected {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        model.selectResource(.pods)

        for _ in 0..<40 {
            if await recorder.count == AppModel.dashboardResourceItems.count {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let requestedNames = await recorder.resourceNames()
        let expectedNames = Set(AppModel.dashboardResourceItems.map { dashboardAPIResource(for: $0).name })
        #expect(Set(requestedNames) == expectedNames)
        #expect(model.selectedResource == .pods)
    }

    @MainActor
    @Test func appModelLoadsResourceDetailForSelectedRow() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            resourceDetailService: SucceedingResourceDetailService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods),
              let row = snapshot.items.first else {
            Issue.record("Expected loaded resource row")
            return
        }

        model.loadResourceDetail(for: .pods, row: row)
        try await waitForResourceDetail(model, resource: .pods, row: row)

        guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: row) else {
            Issue.record("Expected loaded resource detail")
            return
        }

        #expect(detail.query.name == "web-0")
        #expect(detail.query.namespace == "vibekube-demo")
        #expect(detail.yaml.contains("kind: Pod"))
        #expect(detail.yaml.contains("name: web-0"))
        #expect(detail.yaml.contains("namespace: vibekube-demo"))

        let environment = try #require(detail.summary.environment.first)
        #expect(environment.envFrom.isEmpty)
        #expect(environment.variables.contains {
            $0.name == "APP_MODE" &&
                $0.literalValue == "demo" &&
                $0.source?.kind == .configMapKeyRef &&
                $0.source?.name == "web-config" &&
                $0.source?.key == "APP_MODE"
        })
        #expect(environment.variables.filter { $0.name == "PUBLIC_GREETING" }.count == 1)
        #expect(environment.variables.contains {
            $0.name == "PUBLIC_GREETING" &&
                $0.literalValue == "hello-from-configmap" &&
                $0.source?.kind == .configMapKeyRef &&
                $0.source?.name == "web-config" &&
                $0.source?.key == "PUBLIC_GREETING"
        })
        #expect(environment.variables.contains {
            $0.name == "EXTRA_API_TOKEN" &&
                $0.literalValue == nil &&
                $0.source?.kind == .secretKeyRef &&
                $0.source?.name == "web-secrets" &&
                $0.source?.key == "API_TOKEN"
        })
        #expect(!environment.variables.contains { $0.name == "EXTRA_db-password" })
    }

    @MainActor
    @Test func appModelLoadsResourceEventsForSelectedDetail() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            resourceDetailService: SucceedingResourceDetailService(),
            resourceEventService: SucceedingResourceEventService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let row = listSnapshot.items.first else {
            Issue.record("Expected loaded resource row")
            return
        }

        model.loadResourceDetail(for: .pods, row: row)
        try await waitForResourceDetail(model, resource: .pods, row: row)

        guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: row) else {
            Issue.record("Expected loaded resource detail")
            return
        }

        model.loadResourceEvents(for: detail)
        try await waitForResourceEvents(model, detail: detail)

        guard case .loaded(let events) = model.resourceEventsState(for: detail) else {
            Issue.record("Expected loaded resource events")
            return
        }

        #expect(events.query.involvedName == "web-0")
        #expect(events.query.involvedUID == "pod-uid")
        #expect(events.events.map(\.reason) == ["Pulled"])
    }

    @MainActor
    @Test func appModelLoadsPodsWhenSelectingLogsRoute() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.logs)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
            Issue.record("Expected pods to be loaded for Logs")
            return
        }

        #expect(model.selectedResource == .logs)
        #expect(snapshot.items.first?.displayName == "web-0")
    }

    @MainActor
    @Test func appModelLoadsPodLogsForSelectedPod() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: SucceedingLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.logs)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web") else {
            Issue.record("Expected loaded pod logs")
            return
        }

        #expect(logSnapshot.query.namespace == "vibekube-demo")
        #expect(logSnapshot.query.podName == "web-0")
        #expect(logSnapshot.query.containerName == "web")
        #expect(logSnapshot.text.contains("hello from web-0"))
    }

    @MainActor
    @Test func appModelInfersMissingPodKindAndLoadsLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: MissingKindPodResourceListService(),
            logService: SucceedingLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        #expect(pod.displayKind == "Pod")

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web") else {
            Issue.record("Expected loaded pod logs")
            return
        }

        #expect(logSnapshot.query.podName == "web-0")
        #expect(logSnapshot.text.contains("hello from web-0"))
    }

    @MainActor
    @Test func appModelStreamsPodLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: SucceedingLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        model.loadPodLogs(for: pod, containerName: "web")
        try await waitForPodLogs(model, pod: pod, containerName: "web")

        model.loadPodLogs(for: pod, containerName: "web", follow: true)
        try await waitUntil("streaming pod logs appended") {
            if case .loaded(let snapshot) = model.podLogState(for: pod, containerName: "web", follow: true) {
                return snapshot.text.contains("still running")
            }
            return false
        }

        guard case .loaded(let logSnapshot) = model.podLogState(for: pod, containerName: "web", follow: true) else {
            Issue.record("Expected streaming pod logs")
            return
        }

        #expect(logSnapshot.query.follow)
        #expect(logSnapshot.query.tailLines == 200)
        #expect(logSnapshot.text.contains("hello from web-0"))
        #expect(logSnapshot.text.contains("still running"))
        #expect(logSnapshot.text.components(separatedBy: "hello from web-0").count == 2)
    }

    @MainActor
    @Test func appModelAppliesPodWatchAddedEvents() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: WatchingPodResourceListService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitUntil("watched pod appears") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
                return false
            }
            return snapshot.items.contains { $0.displayName == "heartbeat-1" }
        }

        guard case .loaded(let snapshot) = model.resourceListState(for: .pods) else {
            Issue.record("Expected watched pod list")
            return
        }

        #expect(snapshot.items.map(\.displayName).contains("web-0"))
        #expect(snapshot.items.map(\.displayName).contains("heartbeat-1"))
    }

    @MainActor
    @Test func appModelRefreshesOpenPodDetailWhenWatchUpdatesResourceVersion() async throws {
        let detailService = VersionedPodDetailService()
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: ModifyingPodResourceListService(),
            resourceDetailService: detailService,
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let firstSnapshot) = model.resourceListState(for: .pods),
              let initialRow = firstSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected initial pod row")
            return
        }

        model.loadResourceDetail(for: .pods, row: initialRow)
        try await waitForResourceDetail(model, resource: .pods, row: initialRow)

        guard case .loaded(let initialDetail) = model.resourceDetailState(for: .pods, row: initialRow) else {
            Issue.record("Expected initial pod detail")
            return
        }
        #expect(initialDetail.summary.resourceVersion == "10")

        try await waitUntil("watched pod version appears") {
            guard case .loaded(let snapshot) = model.resourceListState(for: .pods),
                  let updatedRow = snapshot.items.first(where: { $0.displayName == "web-0" }) else {
                return false
            }
            return updatedRow.metadata.resourceVersion == "11"
        }

        guard case .loaded(let updatedSnapshot) = model.resourceListState(for: .pods),
              let updatedRow = updatedSnapshot.items.first(where: { $0.displayName == "web-0" }) else {
            Issue.record("Expected updated pod row")
            return
        }

        model.loadResourceDetail(for: .pods, row: updatedRow)
        try await waitUntil("pod detail refreshed for watched version") {
            guard case .loaded(let detail) = model.resourceDetailState(for: .pods, row: updatedRow) else {
                return false
            }
            return detail.summary.resourceVersion == "11"
        }

        #expect(await detailService.callCount() >= 2)
    }

    @MainActor
    @Test func appModelDownloadsAllPreviousPodLogs() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceListService: SucceedingResourceListService(),
            logService: AllPreviousLogService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.selectResource(.pods)
        try await waitForResourceList(model, .pods)

        guard case .loaded(let listSnapshot) = model.resourceListState(for: .pods),
              let pod = listSnapshot.items.first else {
            Issue.record("Expected pod row")
            return
        }

        let text = try await model.podLogsText(
            for: pod,
            containerName: "web",
            timestamps: true,
            previous: true,
            tailLines: nil
        )

        #expect(text.contains("previous crash"))
    }

    @MainActor
    @Test func appModelRevealsEnvSecretValue() async throws {
        let model = AppModel(
            clusters: ClusterSummary.preview,
            connectionService: SucceedingConnectionService(),
            resourceDetailService: SucceedingResourceDetailService(),
            loadedKubeconfig: kubeconfig()
        )

        model.connectSelectedCluster()
        try await waitForConnectionState(model, .connected)

        model.revealEnvSecretValue(
            namespace: "vibekube-demo",
            secretName: "web-secrets",
            key: "db-password"
        )
        try await waitForEnvSecretValue(model, namespace: "vibekube-demo", secretName: "web-secrets", key: "db-password")

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

@MainActor
private func waitForConnectionState(
    _ model: AppModel,
    _ state: ConnectionState
) async throws {
    try await waitUntil("connection state \(state.rawValue)") {
        model.selectedConnectionState == state
    }
}

@MainActor
private func waitForResourceList(
    _ model: AppModel,
    _ resource: ResourceNavigationItem
) async throws {
    try await waitUntil("\(resource.title) list loaded") {
        if case .loaded = model.resourceListState(for: resource) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForResourceDetail(
    _ model: AppModel,
    resource: ResourceNavigationItem,
    row: KubernetesUnstructuredResource
) async throws {
    try await waitUntil("\(resource.title) detail loaded") {
        if case .loaded = model.resourceDetailState(for: resource, row: row) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForResourceEvents(
    _ model: AppModel,
    detail: ResourceDetailSnapshot
) async throws {
    try await waitUntil("resource events loaded") {
        if case .loaded = model.resourceEventsState(for: detail) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForPodLogs(
    _ model: AppModel,
    pod: KubernetesUnstructuredResource,
    containerName: String?,
    follow: Bool = false
) async throws {
    try await waitUntil("pod logs loaded") {
        if case .loaded = model.podLogState(for: pod, containerName: containerName, follow: follow) {
            return true
        }
        return false
    }
}

@MainActor
private func waitForEnvSecretValue(
    _ model: AppModel,
    namespace: String?,
    secretName: String?,
    key: String?
) async throws {
    try await waitUntil("env secret value loaded") {
        if case .loaded = model.envSecretValueState(namespace: namespace, secretName: secretName, key: key) {
            return true
        }
        return false
    }
}

@MainActor
private func waitUntil(
    _ description: String,
    condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<60 {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }

    Issue.record("Timed out waiting for \(description)")
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
                            KubernetesAPIResource(name: "pods", singularName: "", namespaced: true, kind: "Pod", verbs: ["get", "list", "watch"], shortNames: nil, categories: nil),
                            KubernetesAPIResource(name: "configmaps", singularName: "", namespaced: true, kind: "ConfigMap", verbs: ["get"], shortNames: nil, categories: nil),
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
    var delayNanoseconds: UInt64 = 2_000_000

    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        try await Task.sleep(nanoseconds: delayNanoseconds)
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

private struct WatchingPodResourceListService: KubernetesResourceListServicing {
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
                  "metadata": {
                    "resourceVersion": "10"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "10"
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

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            #expect(resource.name == "pods")
            #expect(resourceVersion == "10")

            do {
                let pod = try JSONDecoder().decode(
                    KubernetesUnstructuredResource.self,
                    from: Data(
                        """
                        {
                          "apiVersion": "v1",
                          "kind": "Pod",
                          "metadata": {
                            "name": "heartbeat-1",
                            "namespace": "\(namespace ?? "vibekube-demo")",
                            "uid": "heartbeat-uid",
                            "resourceVersion": "11"
                          },
                          "status": {
                            "phase": "Succeeded"
                          }
                        }
                        """.utf8
                    )
                )
                continuation.yield(
                    KubernetesWatchEvent(
                        type: .added,
                        object: pod
                    )
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct ModifyingPodResourceListService: KubernetesResourceListServicing {
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
                  "metadata": {
                    "resourceVersion": "10"
                  },
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Pod",
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "web-uid",
                        "resourceVersion": "10"
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

    func watchResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        resourceVersion: String?
    ) -> AsyncThrowingStream<KubernetesWatchEvent<KubernetesUnstructuredResource>, Error> {
        AsyncThrowingStream { continuation in
            do {
                let pod = try JSONDecoder().decode(
                    KubernetesUnstructuredResource.self,
                    from: Data(
                        """
                        {
                          "apiVersion": "v1",
                          "kind": "Pod",
                          "metadata": {
                            "name": "web-0",
                            "namespace": "\(namespace ?? "vibekube-demo")",
                            "uid": "web-uid",
                            "resourceVersion": "11"
                          },
                          "status": {
                            "phase": "Running"
                          }
                        }
                        """.utf8
                    )
                )
                continuation.yield(
                    KubernetesWatchEvent(
                        type: .modified,
                        object: pod
                    )
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private actor VersionedPodDetailService: KubernetesResourceDetailServicing {
    private var calls = 0

    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        calls += 1
        let resourceVersion = calls == 1 ? "10" : "11"
        return try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "web-uid",
                    "resourceVersion": "\(resourceVersion)"
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
                """.utf8
            )
        )
    }

    func callCount() -> Int {
        calls
    }
}

private struct MissingKindPodResourceListService: KubernetesResourceListServicing {
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
        if resource.name == "configmaps" {
            return try JSONDecoder().decode(
                KubernetesResourceDetail.self,
                from: Data(
                    """
                    {
                      "apiVersion": "v1",
                      "kind": "ConfigMap",
                      "metadata": {
                        "name": "\(name)",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "data": {
                        "APP_MODE": "demo",
                        "PUBLIC_GREETING": "hello-from-configmap"
                      }
                    }
                    """.utf8
                )
            )
        }

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
                        "API_TOKEN": "dGVzdC10b2tlbg==",
                        "db-password": "dGVzdC1wYXNzd29yZA=="
                      },
                      "type": "Opaque"
                    }
                    """.utf8
                )
            )
        }

        let namespaceLine = namespace.map { #""namespace": "\#($0)","# } ?? ""
        let specLine = resource.name == "pods" ?
            """
            ,
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx:1.27-alpine",
                        "env": [
                          {
                            "name": "PUBLIC_GREETING",
                            "valueFrom": {
                              "configMapKeyRef": {
                                "name": "web-config",
                                "key": "PUBLIC_GREETING"
                              }
                            }
                          }
                        ],
                        "envFrom": [
                          {
                            "configMapRef": {
                              "name": "web-config"
                            }
                          },
                          {
                            "prefix": "EXTRA_",
                            "secretRef": {
                              "name": "web-secrets"
                            }
                          }
                        ]
                      }
                    ]
                  }
            """ : ""
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
                  \(specLine)
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

private struct SucceedingLogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        #expect(contextName == "kind-vibekube-dev")
        #expect(namespace == "vibekube-demo")
        #expect(podName == "web-0")
        #expect(options.container == "web")
        #expect(options.tailLines == 200)
        #expect(options.timestamps == true)
        #expect(options.follow == false)

        return "2026-06-15T10:01:00Z hello from web-0"
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            #expect(contextName == "kind-vibekube-dev")
            #expect(namespace == "vibekube-demo")
            #expect(podName == "web-0")
            #expect(options.container == "web")
            #expect(options.follow == true)
            #expect(options.tailLines == 0)

            continuation.yield("2026-06-15T10:01:01Z still running\n")
            continuation.finish()
        }
    }
}

private struct AllPreviousLogService: KubernetesLogServicing {
    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        #expect(contextName == "kind-vibekube-dev")
        #expect(namespace == "vibekube-demo")
        #expect(podName == "web-0")
        #expect(options.container == "web")
        #expect(options.previous == true)
        #expect(options.tailLines == nil)
        #expect(options.timestamps == true)
        #expect(options.follow == false)

        return "2026-06-15T10:00:59Z previous crash"
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
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
