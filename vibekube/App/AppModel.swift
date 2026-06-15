import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var clusters: [ClusterSummary]
    @Published var selectedClusterID: ClusterSummary.ID?
    @Published var selectedResource: ResourceNavigationItem?
    @Published var searchText = ""
    @Published private(set) var kubeconfigState: KubeconfigDiscoveryState
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var connectionErrorMessage: String?
    @Published private(set) var discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot]
    @Published private(set) var resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]
    @Published private(set) var resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]
    @Published private var selectedNamespaceByContextID: [ClusterSummary.ID: String]

    private let kubeconfigLoader: KubeconfigLoader?
    private let connectionService: KubernetesConnectionServicing?
    private let resourceListService: KubernetesResourceListServicing?
    private let resourceDetailService: KubernetesResourceDetailServicing?
    private var loadedKubeconfig: Kubeconfig
    private var connectionTask: Task<Void, Never>?
    private var resourceListTask: Task<Void, Never>?
    private var resourceDetailTask: Task<Void, Never>?

    static let allNamespacesSelection = "__vibekube_all_namespaces__"

    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        if environment["VIBEKUBE_USE_PREVIEW_CLUSTERS"] == "1" {
            let usePreviewData = environment["VIBEKUBE_USE_PREVIEW_DATA"] == "1"
            self.init(
                clusters: ClusterSummary.preview,
                kubeconfigState: .loaded(contextCount: ClusterSummary.preview.count, sourceCount: 1),
                kubeconfigLoader: nil,
                connectionService: usePreviewData ? PreviewKubernetesConnectionService() : nil,
                resourceListService: usePreviewData ? PreviewKubernetesResourceListService() : nil,
                resourceDetailService: usePreviewData ? PreviewKubernetesResourceDetailService() : nil
            )
        } else {
            let execCredentialProvider = DefaultKubernetesExecCredentialProvider()
            self.init(
                clusters: [],
                kubeconfigState: .notLoaded,
                kubeconfigLoader: KubeconfigLoader(environment: environment),
                connectionService: KubernetesConnectionService(execCredentialProvider: execCredentialProvider),
                resourceListService: KubernetesResourceListService(execCredentialProvider: execCredentialProvider),
                resourceDetailService: KubernetesResourceDetailService(execCredentialProvider: execCredentialProvider)
            )
            reloadKubeconfig()
        }
    }

    init(
        clusters: [ClusterSummary],
        kubeconfigState: KubeconfigDiscoveryState? = nil,
        kubeconfigLoader: KubeconfigLoader? = nil,
        connectionService: KubernetesConnectionServicing? = nil,
        resourceListService: KubernetesResourceListServicing? = nil,
        resourceDetailService: KubernetesResourceDetailServicing? = nil,
        loadedKubeconfig: Kubeconfig? = nil,
        discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot] = [:],
        resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]? = nil,
        resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]? = nil,
        selectedNamespaceByContextID: [ClusterSummary.ID: String] = [:]
    ) {
        self.clusters = clusters
        self.selectedClusterID = clusters.first?.id
        self.selectedResource = .dashboard
        self.kubeconfigState = kubeconfigState ?? .loaded(contextCount: clusters.count, sourceCount: 1)
        self.kubeconfigLoader = kubeconfigLoader
        self.connectionService = connectionService
        self.resourceListService = resourceListService
        self.resourceDetailService = resourceDetailService
        self.loadedKubeconfig = loadedKubeconfig ?? .empty
        self.discoveryByContextID = discoveryByContextID
        self.resourceListStateByQuery = resourceListStateByQuery ?? [:]
        self.resourceDetailStateByQuery = resourceDetailStateByQuery ?? [:]
        self.selectedNamespaceByContextID = selectedNamespaceByContextID
    }

    var selectedCluster: ClusterSummary? {
        clusters.first { $0.id == selectedClusterID }
    }

    var selectedConnectionState: ConnectionState {
        selectedCluster?.connectionState ?? .disconnected
    }

    var selectedDiscovery: KubernetesDiscoverySnapshot? {
        selectedClusterID.flatMap { discoveryByContextID[$0] }
    }

    var selectedNamespaceSelection: String {
        guard let selectedClusterID else {
            return Self.allNamespacesSelection
        }

        if let selectedNamespace = selectedNamespaceByContextID[selectedClusterID] {
            return selectedNamespace
        }

        return Self.allNamespacesSelection
    }

    var selectedNamespaceTitle: String {
        namespaceTitle(for: selectedNamespaceSelection)
    }

    var namespaceSelectionOptions: [String] {
        guard let selectedCluster else {
            return []
        }

        let discoveredNamespaces = selectedDiscovery?.namespaceDiscovery.items.map(\.name) ?? []
        return orderedUnique(
            [Self.allNamespacesSelection, selectedCluster.namespace] + discoveredNamespaces
        )
    }

    var namespaceAccessErrorMessage: String? {
        selectedDiscovery?.namespaceDiscovery.errorMessage
    }

    var canConnectSelectedCluster: Bool {
        guard let selectedCluster else { return false }
        return selectedCluster.connectionState.canAttemptConnection
    }

    func selectCluster(id: ClusterSummary.ID?) {
        connectionTask?.cancel()
        resourceListTask?.cancel()
        resourceDetailTask?.cancel()
        selectedClusterID = id
        selectedResource = .dashboard
        connectionErrorMessage = nil
    }

    func selectResource(_ resource: ResourceNavigationItem) {
        selectedResource = resource
        loadResourceList(for: resource)
    }

    func selectNamespace(_ namespace: String) {
        guard let selectedClusterID else {
            return
        }

        selectedNamespaceByContextID[selectedClusterID] = namespace
        resourceDetailTask?.cancel()
        if let selectedResource {
            loadResourceList(for: selectedResource, force: true)
        }
    }

    func namespaceTitle(for namespace: String) -> String {
        namespace == Self.allNamespacesSelection ? "All Namespaces" : namespace
    }

    func refresh() {
        if let selectedResource,
           selectedConnectionState == .connected,
           selectedResource.discoveredResource(in: selectedDiscovery) != nil {
            loadResourceList(for: selectedResource, force: true)
        } else {
            reloadKubeconfig()
        }

        lastRefreshedAt = Date()
    }

    func reloadKubeconfig() {
        guard let kubeconfigLoader else { return }

        let previousSelection = selectedClusterID
        let result = kubeconfigLoader.load()
        let discoveredClusters = result.kubeconfig.clusterSummaries()
        loadedKubeconfig = result.kubeconfig
        clusters = discoveredClusters
        connectionErrorMessage = nil
        let validContextIDs = Set(discoveredClusters.map(\.id))
        discoveryByContextID = discoveryByContextID.filter { validContextIDs.contains($0.key) }
        resourceListStateByQuery = resourceListStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        resourceDetailStateByQuery = resourceDetailStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        selectedNamespaceByContextID = selectedNamespaceByContextID.filter { validContextIDs.contains($0.key) }

        if discoveredClusters.isEmpty {
            selectedClusterID = nil
            kubeconfigState = result.hasExistingSource
                ? .failed(message: result.issueSummary ?? "No contexts were found in kubeconfig.")
                : .missing(paths: result.requestedPaths.map(\.displayPath))
            return
        }

        if let previousSelection,
           discoveredClusters.contains(where: { $0.id == previousSelection }) {
            selectedClusterID = previousSelection
        } else if let current = discoveredClusters.first(where: \.isCurrentContext) {
            selectedClusterID = current.id
        } else {
            selectedClusterID = discoveredClusters.first?.id
        }

        kubeconfigState = .loaded(
            contextCount: discoveredClusters.count,
            sourceCount: result.existingSources.count
        )
    }

    func connectSelectedCluster() {
        guard let selectedClusterID else { return }

        connectionTask?.cancel()
        resourceListTask?.cancel()
        resourceDetailTask?.cancel()
        connectionErrorMessage = nil

        guard let connectionService else {
            updateCluster(id: selectedClusterID) { cluster in
                cluster.connectionState = .connected
                cluster.lastSeenAt = Date()
            }
            discoveryByContextID[selectedClusterID] = .preview
            if let selectedResource {
                loadResourceList(for: selectedResource)
            }
            return
        }

        let kubeconfig = loadedKubeconfig
        updateCluster(id: selectedClusterID) { cluster in
            cluster.connectionState = .connecting
            cluster.kubernetesVersion = nil
            cluster.lastSeenAt = nil
        }
        discoveryByContextID[selectedClusterID] = nil
        resourceListStateByQuery = resourceListStateByQuery.filter { $0.key.contextID != selectedClusterID }
        resourceDetailStateByQuery = resourceDetailStateByQuery.filter { $0.key.contextID != selectedClusterID }

        connectionTask = Task { [weak self] in
            do {
                let snapshot = try await connectionService.connect(
                    contextName: selectedClusterID,
                    kubeconfig: kubeconfig
                )

                try Task.checkCancellation()
                self?.finishConnection(contextID: selectedClusterID, snapshot: snapshot)
            } catch is CancellationError {
                self?.cancelConnection(contextID: selectedClusterID)
            } catch {
                self?.failConnection(contextID: selectedClusterID, error: error)
            }
        }
    }

    func disconnectSelectedCluster() {
        connectionTask?.cancel()
        resourceListTask?.cancel()
        resourceDetailTask?.cancel()
        connectionTask = nil
        resourceListTask = nil
        resourceDetailTask = nil
        connectionErrorMessage = nil

        updateSelectedCluster { cluster in
            cluster.connectionState = .disconnected
            cluster.kubernetesVersion = nil
            cluster.lastSeenAt = nil
        }

        if let selectedClusterID {
            discoveryByContextID[selectedClusterID] = nil
            resourceListStateByQuery = resourceListStateByQuery.filter { $0.key.contextID != selectedClusterID }
            resourceDetailStateByQuery = resourceDetailStateByQuery.filter { $0.key.contextID != selectedClusterID }
        }
    }

    func resourceListState(for resource: ResourceNavigationItem) -> ResourceListLoadState {
        guard let query = resourceListQuery(for: resource) else {
            return .idle
        }

        return resourceListStateByQuery[query] ?? .idle
    }

    func resourceListTaskID(for resource: ResourceNavigationItem) -> String {
        resourceListQuery(for: resource)?.id ?? "\(selectedClusterID ?? "none")|\(resource.id)|\(selectedConnectionState.rawValue)"
    }

    func loadResourceList(for resource: ResourceNavigationItem, force: Bool = false) {
        guard selectedConnectionState == .connected,
              let query = resourceListQuery(for: resource),
              query.resource.verbs.contains("list") else {
            return
        }

        if !force {
            switch resourceListStateByQuery[query] {
            case .some(.loaded), .some(.loading):
                return
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        resourceListTask?.cancel()
        resourceListStateByQuery[query] = .loading

        guard let resourceListService else {
            finishResourceList(
                query: query,
                response: KubernetesUnstructuredResourceList(
                    apiVersion: query.resource.groupVersion,
                    kind: "\(query.resource.kind)List",
                    metadata: nil,
                    items: []
                )
            )
            return
        }

        let kubeconfig = loadedKubeconfig
        let namespace = namespaceForRequest(query)
        resourceListTask = Task { [weak self] in
            do {
                let response = try await resourceListService.listResources(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: query.resource,
                    namespace: namespace
                )

                try Task.checkCancellation()
                self?.finishResourceList(query: query, response: response)
            } catch is CancellationError {
                self?.cancelResourceList(query: query)
            } catch {
                self?.failResourceList(query: query, error: error)
            }
        }
    }

    func resourceDetailState(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource
    ) -> ResourceDetailLoadState {
        guard let query = resourceDetailQuery(for: resource, row: row) else {
            return .idle
        }

        return resourceDetailStateByQuery[query] ?? .idle
    }

    func resourceDetailTaskID(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource
    ) -> String {
        resourceDetailQuery(for: resource, row: row)?.id ?? "\(selectedClusterID ?? "none")|\(resource.id)|\(row.id)"
    }

    func loadResourceDetail(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        force: Bool = false
    ) {
        guard selectedConnectionState == .connected,
              let query = resourceDetailQuery(for: resource, row: row),
              query.resource.verbs.contains("get") else {
            return
        }

        if !force {
            switch resourceDetailStateByQuery[query] {
            case .some(.loaded), .some(.loading):
                return
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        resourceDetailTask?.cancel()
        resourceDetailStateByQuery[query] = .loading

        guard let resourceDetailService else {
            failResourceDetail(query: query, error: KubernetesClientError.unavailable("Resource detail service is unavailable."))
            return
        }

        let kubeconfig = loadedKubeconfig
        resourceDetailTask = Task { [weak self] in
            do {
                let detail = try await resourceDetailService.resourceDetail(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: query.resource,
                    namespace: query.namespace,
                    name: query.name
                )

                try Task.checkCancellation()
                self?.finishResourceDetail(query: query, detail: detail)
            } catch is CancellationError {
                self?.cancelResourceDetail(query: query)
            } catch {
                self?.failResourceDetail(query: query, error: error)
            }
        }
    }

    private func cancelConnection(contextID: ClusterSummary.ID) {
        updateCluster(id: contextID) { cluster in
            if cluster.connectionState == .connecting {
                cluster.connectionState = .disconnected
            }
        }
    }

    private func finishConnection(contextID: ClusterSummary.ID, snapshot: KubernetesConnectionSnapshot) {
        updateCluster(id: contextID) { cluster in
            cluster.connectionState = .connected
            cluster.kubernetesVersion = snapshot.version.gitVersion
            cluster.lastSeenAt = Date()
        }
        discoveryByContextID[contextID] = snapshot.discovery

        if selectedNamespaceByContextID[contextID] == nil {
            selectedNamespaceByContextID[contextID] = Self.allNamespacesSelection
        }

        if selectedClusterID == contextID {
            connectionErrorMessage = nil
        }

        if selectedClusterID == contextID, let selectedResource {
            loadResourceList(for: selectedResource)
        }
    }

    private func failConnection(contextID: ClusterSummary.ID, error: Error) {
        let clientError = error as? KubernetesClientError
        updateCluster(id: contextID) { cluster in
            cluster.connectionState = clientError?.connectionState ?? .unavailable
            cluster.kubernetesVersion = nil
            cluster.lastSeenAt = nil
        }

        if selectedClusterID == contextID {
            connectionErrorMessage = error.localizedDescription
        }
        discoveryByContextID[contextID] = nil
        resourceListStateByQuery = resourceListStateByQuery.filter { $0.key.contextID != contextID }
        resourceDetailStateByQuery = resourceDetailStateByQuery.filter { $0.key.contextID != contextID }
    }

    private func finishResourceList(
        query: ResourceListQuery,
        response: KubernetesUnstructuredResourceList
    ) {
        resourceListStateByQuery[query] = .loaded(
            ResourceListSnapshot(
                query: query,
                items: response.items,
                resourceVersion: response.metadata?.resourceVersion,
                continueToken: response.metadata?.continueToken,
                loadedAt: Date()
            )
        )
    }

    private func cancelResourceList(query: ResourceListQuery) {
        if resourceListStateByQuery[query] == .loading {
            resourceListStateByQuery[query] = .idle
        }
    }

    private func failResourceList(query: ResourceListQuery, error: Error) {
        resourceListStateByQuery[query] = .failed(error.localizedDescription)
    }

    private func finishResourceDetail(
        query: ResourceDetailQuery,
        detail: KubernetesResourceDetail
    ) {
        resourceDetailStateByQuery[query] = .loaded(
            ResourceDetailSnapshot(
                query: query,
                yaml: detail.yaml,
                summary: detail.summary,
                loadedAt: Date()
            )
        )
    }

    private func cancelResourceDetail(query: ResourceDetailQuery) {
        if resourceDetailStateByQuery[query] == .loading {
            resourceDetailStateByQuery[query] = .idle
        }
    }

    private func failResourceDetail(query: ResourceDetailQuery, error: Error) {
        resourceDetailStateByQuery[query] = .failed(error.localizedDescription)
    }

    private func updateSelectedCluster(_ update: (inout ClusterSummary) -> Void) {
        guard let selectedClusterID else {
            return
        }

        updateCluster(id: selectedClusterID, update)
    }

    private func updateCluster(id: ClusterSummary.ID, _ update: (inout ClusterSummary) -> Void) {
        guard let index = clusters.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&clusters[index])
    }

    private func resourceListQuery(for resource: ResourceNavigationItem) -> ResourceListQuery? {
        guard let selectedClusterID,
              let discoveredResource = resource.discoveredResource(in: selectedDiscovery) else {
            return nil
        }

        return ResourceListQuery(
            contextID: selectedClusterID,
            resource: discoveredResource,
            namespaceSelection: selectedNamespaceSelection
        )
    }

    private func resourceDetailQuery(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource
    ) -> ResourceDetailQuery? {
        guard let selectedClusterID,
              let discoveredResource = resource.discoveredResource(in: selectedDiscovery),
              let name = row.metadata.name,
              !name.isEmpty else {
            return nil
        }

        let namespace = namespaceForDetailRequest(row: row, resource: discoveredResource)
        if discoveredResource.namespaced, namespace == nil {
            return nil
        }

        return ResourceDetailQuery(
            contextID: selectedClusterID,
            resource: discoveredResource,
            namespace: namespace,
            name: name
        )
    }

    private func namespaceForRequest(_ query: ResourceListQuery) -> String? {
        guard query.resource.namespaced,
              query.namespaceSelection != Self.allNamespacesSelection else {
            return nil
        }

        return query.namespaceSelection
    }

    private func namespaceForDetailRequest(
        row: KubernetesUnstructuredResource,
        resource: KubernetesDiscoveredResource
    ) -> String? {
        guard resource.namespaced else {
            return nil
        }

        if let namespace = row.metadata.namespace, !namespace.isEmpty {
            return namespace
        }

        guard selectedNamespaceSelection != Self.allNamespacesSelection else {
            return nil
        }

        return selectedNamespaceSelection
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }
}

private struct PreviewKubernetesConnectionService: KubernetesConnectionServicing {
    func connect(contextName: String, kubeconfig: Kubeconfig) async throws -> KubernetesConnectionSnapshot {
        KubernetesConnectionSnapshot(
            version: KubernetesVersion(
                major: "1",
                minor: "30",
                gitVersion: "v1.30.0",
                gitCommit: nil,
                platform: nil
            ),
            discovery: .preview
        )
    }
}

private struct PreviewKubernetesResourceListService: KubernetesResourceListServicing {
    func listResources(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?
    ) async throws -> KubernetesUnstructuredResourceList {
        guard resource.name == "pods" else {
            return try decodeList(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)List",
                  "items": []
                }
                """
            )
        }

        return try decodeList(
            """
            {
              "apiVersion": "v1",
              "kind": "PodList",
              "items": [
                {
                  "apiVersion": "v1",
                  "kind": "Pod",
                  "metadata": {
                    "name": "web-0",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "preview-pod-web-0",
                    "creationTimestamp": "2026-06-15T10:00:00Z",
                    "labels": {
                      "app": "web",
                      "tier": "frontend"
                    }
                  },
                  "status": {
                    "phase": "Running"
                  }
                }
              ]
            }
            """
        )
    }

    private func decodeList(_ json: String) throws -> KubernetesUnstructuredResourceList {
        try JSONDecoder().decode(KubernetesUnstructuredResourceList.self, from: Data(json.utf8))
    }
}

private struct PreviewKubernetesResourceDetailService: KubernetesResourceDetailServicing {
    func resourceDetail(
        contextName: String,
        kubeconfig: Kubeconfig,
        resource: KubernetesDiscoveredResource,
        namespace: String?,
        name: String
    ) async throws -> KubernetesResourceDetail {
        try JSONDecoder().decode(
            KubernetesResourceDetail.self,
            from: Data(
                """
                {
                  "apiVersion": "\(resource.groupVersion)",
                  "kind": "\(resource.kind)",
                  "metadata": {
                    "name": "\(name)",
                    "namespace": "\(namespace ?? "vibekube-demo")",
                    "uid": "preview-pod-web-0",
                    "resourceVersion": "420",
                    "creationTimestamp": "2026-06-15T10:00:00Z",
                    "labels": {
                      "app": "web",
                      "tier": "frontend"
                    },
                    "annotations": {
                      "kubectl.kubernetes.io/last-applied-configuration": "{\\"kind\\":\\"Pod\\"}",
                      "vibekube.io/demo": "true"
                    },
                    "ownerReferences": [
                      {
                        "apiVersion": "apps/v1",
                        "kind": "ReplicaSet",
                        "name": "web-74fbd884",
                        "controller": true
                      }
                    ]
                  },
                  "spec": {
                    "containers": [
                      {
                        "name": "web",
                        "image": "nginx:1.27",
                        "ports": [
                          {
                            "containerPort": 8080
                          }
                        ]
                      }
                    ]
                  },
                  "status": {
                    "phase": "Running",
                    "conditions": [
                      {
                        "type": "Ready",
                        "status": "True",
                        "reason": "ContainersReady",
                        "message": "All containers are ready.",
                        "lastTransitionTime": "2026-06-15T10:01:00Z"
                      }
                    ],
                    "containerStatuses": [
                      {
                        "name": "web",
                        "ready": true,
                        "restartCount": 0
                      }
                    ]
                  }
                }
                """.utf8
            )
        )
    }
}
