import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var clusters: [ClusterSummary]
    @Published private(set) var route: AppRoute
    @Published var searchText = ""
    @Published private(set) var kubeconfigState: KubeconfigDiscoveryState
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var connectionErrorMessage: String?
    @Published private(set) var discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot]
    @Published private(set) var resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]
    @Published private(set) var resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]
    @Published private(set) var resourceEventsStateByQuery: [ResourceEventsQuery: ResourceEventsLoadState]
    @Published private(set) var envSecretValueStateByQuery: [ResourceEnvSecretValueQuery: ResourceEnvSecretValueLoadState]
    @Published private(set) var dashboardMetricsStateByQuery: [DashboardMetricsQuery: DashboardMetricsLoadState]
    @Published private(set) var searchFocusRequestID = 0
    @Published private var selectedNamespaceByContextID: [ClusterSummary.ID: String]

    private let kubeconfigLoader: KubeconfigLoader?
    private let connectionService: KubernetesConnectionServicing?
    private let resourceListService: KubernetesResourceListServicing?
    private let resourceDetailService: KubernetesResourceDetailServicing?
    private let resourceEventService: KubernetesResourceEventServicing?
    private let metricsService: KubernetesMetricsServicing?
    private var userPreferences: UserPreferencesProviding
    private var loadedKubeconfig: Kubeconfig
    private var connectionTask: Task<Void, Never>?
    private var resourceListTasksByQuery: [ResourceListQuery: Task<Void, Never>]
    private var resourceDetailTask: Task<Void, Never>?
    private var resourceEventsTask: Task<Void, Never>?
    private var dashboardMetricsTask: Task<Void, Never>?
    private var envSecretValueTasksByQuery: [ResourceEnvSecretValueQuery: Task<Void, Never>]

    static let allNamespacesSelection = DashboardMetricsQuery.allNamespacesSelection
    static let dashboardResourceItems: [ResourceNavigationItem] = [
        .nodes,
        .pods
    ]

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
                resourceDetailService: usePreviewData ? PreviewKubernetesResourceDetailService() : nil,
                resourceEventService: usePreviewData ? PreviewKubernetesResourceEventService() : nil,
                metricsService: usePreviewData ? PreviewKubernetesMetricsService() : nil,
                userPreferences: InMemoryUserPreferences()
            )
        } else {
            let execCredentialProvider = DefaultKubernetesExecCredentialProvider()
            self.init(
                clusters: [],
                kubeconfigState: .notLoaded,
                kubeconfigLoader: KubeconfigLoader(environment: environment),
                connectionService: KubernetesConnectionService(execCredentialProvider: execCredentialProvider),
                resourceListService: KubernetesResourceListService(execCredentialProvider: execCredentialProvider),
                resourceDetailService: KubernetesResourceDetailService(execCredentialProvider: execCredentialProvider),
                resourceEventService: KubernetesResourceEventService(execCredentialProvider: execCredentialProvider),
                metricsService: KubernetesMetricsService(execCredentialProvider: execCredentialProvider),
                userPreferences: UserDefaultsUserPreferences()
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
        resourceEventService: KubernetesResourceEventServicing? = nil,
        metricsService: KubernetesMetricsServicing? = nil,
        userPreferences: UserPreferencesProviding? = nil,
        loadedKubeconfig: Kubeconfig? = nil,
        discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot] = [:],
        resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]? = nil,
        resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]? = nil,
        resourceEventsStateByQuery: [ResourceEventsQuery: ResourceEventsLoadState]? = nil,
        envSecretValueStateByQuery: [ResourceEnvSecretValueQuery: ResourceEnvSecretValueLoadState]? = nil,
        dashboardMetricsStateByQuery: [DashboardMetricsQuery: DashboardMetricsLoadState]? = nil,
        selectedNamespaceByContextID: [ClusterSummary.ID: String] = [:]
    ) {
        var userPreferences = userPreferences ?? InMemoryUserPreferences()
        let initialClusterID = Self.initialClusterID(
            in: clusters,
            preferredClusterID: userPreferences.selectedContextID
        )
        let initialResource = Self.resourceNavigationItem(
            forID: userPreferences.selectedResourceID
        ) ?? .dashboard

        self.clusters = clusters
        self.route = AppRoute(clusterID: initialClusterID, resource: initialResource)
        self.kubeconfigState = kubeconfigState ?? .loaded(contextCount: clusters.count, sourceCount: 1)
        self.kubeconfigLoader = kubeconfigLoader
        self.connectionService = connectionService
        self.resourceListService = resourceListService
        self.resourceDetailService = resourceDetailService
        self.resourceEventService = resourceEventService
        self.metricsService = metricsService
        self.userPreferences = userPreferences
        self.loadedKubeconfig = loadedKubeconfig ?? .empty
        self.discoveryByContextID = discoveryByContextID
        self.resourceListStateByQuery = resourceListStateByQuery ?? [:]
        self.resourceDetailStateByQuery = resourceDetailStateByQuery ?? [:]
        self.resourceEventsStateByQuery = resourceEventsStateByQuery ?? [:]
        self.envSecretValueStateByQuery = envSecretValueStateByQuery ?? [:]
        self.dashboardMetricsStateByQuery = dashboardMetricsStateByQuery ?? [:]
        self.selectedNamespaceByContextID = selectedNamespaceByContextID.isEmpty
            ? userPreferences.selectedNamespaceByContextID
            : selectedNamespaceByContextID
        self.resourceListTasksByQuery = [:]
        self.resourceEventsTask = nil
        self.dashboardMetricsTask = nil
        self.envSecretValueTasksByQuery = [:]

        userPreferences.selectedContextID = initialClusterID
        userPreferences.selectedResourceID = initialResource.rawValue
        self.userPreferences = userPreferences
    }

    var selectedClusterID: ClusterSummary.ID? {
        route.clusterID
    }

    var selectedResource: ResourceNavigationItem? {
        route.resource
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

    var selectedClusterIdentityText: String? {
        guard let selectedCluster else {
            return nil
        }

        return [
            "Context: \(selectedCluster.contextName)",
            "Cluster: \(selectedCluster.name)",
            "Server: \(selectedCluster.server)",
            "Namespace: \(selectedNamespaceTitle)",
            "Auth: \(selectedCluster.authDescription)",
            "Source: \(selectedCluster.sourceName)"
        ].joined(separator: "\n")
    }

    var selectedRouteIdentityText: String? {
        guard let selectedCluster else {
            return nil
        }

        var lines = [
            "Context: \(selectedCluster.contextName)",
            "Route: \(route.resource.title)"
        ]

        if let discoveredResource = route.resource.discoveredResource(in: selectedDiscovery) {
            lines.append("API: \(discoveredResource.groupVersion)/\(discoveredResource.name)")
            lines.append("Kind: \(discoveredResource.kind)")
            lines.append("Scope: \(discoveredResource.scopeTitle)")
            if discoveredResource.namespaced {
                lines.append("Namespace: \(selectedNamespaceTitle)")
            }
        } else if route.resource.requiresDiscoveredResource {
            lines.append("API: Not discovered")
        }

        return lines.joined(separator: "\n")
    }

    var canOpenLogsForSelectedRoute: Bool {
        selectedConnectionState == .connected && route.resource.supportsLogs
    }

    var selectedDashboardSnapshot: ClusterDashboardSnapshot {
        ClusterDashboardSnapshot.make(states: dashboardResourceStates())
    }

    var selectedDashboardResourceUsageSummary: DashboardResourceUsageSummary {
        DashboardResourceUsageSummary.make(
            state: dashboardMetricsState(),
            nodeItems: resourceListSnapshot(for: .nodes)?.items
        )
    }

    func selectCluster(id: ClusterSummary.ID?) {
        guard route.clusterID != id else {
            return
        }

        connectionTask?.cancel()
        cancelResourceListTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelEnvSecretValueTasks()
        navigate(clusterID: id, resource: .dashboard)
        connectionErrorMessage = nil
    }

    func selectResource(_ resource: ResourceNavigationItem) {
        guard route.resource != resource else {
            return
        }

        navigate(clusterID: selectedClusterID, resource: resource)
        if resource == .dashboard {
            loadDashboardResources()
            loadDashboardMetrics()
        } else {
            loadResourceList(for: resource)
        }
    }

    func selectNamespace(_ namespace: String) {
        guard let selectedClusterID else {
            return
        }

        selectedNamespaceByContextID[selectedClusterID] = namespace
        userPreferences.selectedNamespaceByContextID = selectedNamespaceByContextID
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        if selectedResource == .dashboard {
            loadDashboardResources(force: true)
            loadDashboardMetrics(force: true)
        } else if let selectedResource {
            loadResourceList(for: selectedResource, force: true)
        }
    }

    func namespaceTitle(for namespace: String) -> String {
        namespace == Self.allNamespacesSelection ? "All Namespaces" : namespace
    }

    func focusSearchField() {
        searchFocusRequestID += 1
    }

    func clearSearch() {
        searchText = ""
    }

    func openLogsForSelectedRoute() {
        guard canOpenLogsForSelectedRoute else {
            return
        }

        selectResource(.logs)
    }

    func refresh() {
        if selectedResource == .dashboard, selectedConnectionState == .connected {
            loadDashboardResources(force: true)
            loadDashboardMetrics(force: true)
        } else if let selectedResource,
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

        let previousRoute = route
        let result = kubeconfigLoader.load()
        let discoveredClusters = result.kubeconfig.clusterSummaries()
        loadedKubeconfig = result.kubeconfig
        clusters = discoveredClusters
        connectionErrorMessage = nil
        let validContextIDs = Set(discoveredClusters.map(\.id))
        discoveryByContextID = discoveryByContextID.filter { validContextIDs.contains($0.key) }
        resourceListStateByQuery = resourceListStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        resourceDetailStateByQuery = resourceDetailStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        resourceEventsStateByQuery = resourceEventsStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        envSecretValueStateByQuery = envSecretValueStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        dashboardMetricsStateByQuery = dashboardMetricsStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        selectedNamespaceByContextID = selectedNamespaceByContextID.filter { validContextIDs.contains($0.key) }

        if discoveredClusters.isEmpty {
            navigate(clusterID: nil, resource: previousRoute.resource, persist: false)
            kubeconfigState = result.hasExistingSource
                ? .failed(message: result.issueSummary ?? "No contexts were found in kubeconfig.")
                : .missing(paths: result.requestedPaths.map(\.displayPath))
            return
        }

        let preferredSelection = userPreferences.selectedContextID
        if let previousSelection = previousRoute.clusterID,
           discoveredClusters.contains(where: { $0.id == previousSelection }) {
            navigate(clusterID: previousSelection, resource: previousRoute.resource, persist: false)
        } else if let preferredSelection,
                  discoveredClusters.contains(where: { $0.id == preferredSelection }) {
            navigate(clusterID: preferredSelection, resource: previousRoute.resource, persist: false)
        } else if let current = discoveredClusters.first(where: \.isCurrentContext) {
            navigate(clusterID: current.id, resource: previousRoute.resource, persist: false)
        } else {
            navigate(clusterID: discoveredClusters.first?.id, resource: previousRoute.resource, persist: false)
        }

        kubeconfigState = .loaded(
            contextCount: discoveredClusters.count,
            sourceCount: result.existingSources.count
        )
    }

    func connectSelectedCluster() {
        guard let selectedClusterID else { return }

        connectionTask?.cancel()
        cancelResourceListTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelEnvSecretValueTasks()
        connectionErrorMessage = nil

        guard let connectionService else {
            updateCluster(id: selectedClusterID) { cluster in
                cluster.connectionState = .connected
                cluster.lastSeenAt = Date()
            }
            discoveryByContextID[selectedClusterID] = .preview
            if selectedResource == .dashboard {
                loadDashboardResources()
                loadDashboardMetrics()
            } else if let selectedResource {
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
        resourceEventsStateByQuery = resourceEventsStateByQuery.filter { $0.key.contextID != selectedClusterID }
        envSecretValueStateByQuery = envSecretValueStateByQuery.filter { $0.key.contextID != selectedClusterID }
        dashboardMetricsStateByQuery = dashboardMetricsStateByQuery.filter { $0.key.contextID != selectedClusterID }

        connectionTask = Task.detached(priority: .userInitiated) { [weak self, connectionService, kubeconfig] in
            do {
                let snapshot = try await connectionService.connect(
                    contextName: selectedClusterID,
                    kubeconfig: kubeconfig
                )

                try Task.checkCancellation()
                await self?.finishConnection(contextID: selectedClusterID, snapshot: snapshot)
            } catch is CancellationError {
                await self?.cancelConnection(contextID: selectedClusterID)
            } catch {
                await self?.failConnection(contextID: selectedClusterID, error: error)
            }
        }
    }

    func disconnectSelectedCluster() {
        connectionTask?.cancel()
        cancelResourceListTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelEnvSecretValueTasks()
        connectionTask = nil
        resourceDetailTask = nil
        resourceEventsTask = nil
        dashboardMetricsTask = nil
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
            resourceEventsStateByQuery = resourceEventsStateByQuery.filter { $0.key.contextID != selectedClusterID }
            envSecretValueStateByQuery = envSecretValueStateByQuery.filter { $0.key.contextID != selectedClusterID }
            dashboardMetricsStateByQuery = dashboardMetricsStateByQuery.filter { $0.key.contextID != selectedClusterID }
        }
    }

    func resourceListState(for resource: ResourceNavigationItem) -> ResourceListLoadState {
        guard let query = resourceListQuery(for: resource) else {
            return .idle
        }

        return resourceListStateByQuery[query] ?? .idle
    }

    private func resourceListSnapshot(for resource: ResourceNavigationItem) -> ResourceListSnapshot? {
        guard case .loaded(let snapshot) = resourceListState(for: resource) else {
            return nil
        }
        return snapshot
    }

    private func dashboardMetricsState() -> DashboardMetricsLoadState {
        guard let query = dashboardMetricsQuery() else {
            return .idle
        }
        return dashboardMetricsStateByQuery[query] ?? .idle
    }

    func resourceListTaskID(for resource: ResourceNavigationItem) -> String {
        resourceListQuery(for: resource)?.id ?? "\(selectedClusterID ?? "none")|\(resource.id)|\(selectedConnectionState.rawValue)"
    }

    var dashboardTaskID: String {
        [
            selectedClusterID ?? "none",
            selectedNamespaceSelection,
            selectedConnectionState.rawValue,
            selectedDiscovery.map { "\($0.resourceCount)" } ?? "no-discovery"
        ].joined(separator: "|")
    }

    func loadDashboardResources(force: Bool = false) {
        for item in Self.dashboardResourceItems {
            loadResourceList(for: item, force: force)
        }
    }

    func loadDashboardMetrics(force: Bool = false) {
        guard selectedConnectionState == .connected,
              let query = dashboardMetricsQuery() else {
            return
        }

        guard selectedDiscovery?.hasMetricsAPI == true else {
            dashboardMetricsStateByQuery[query] = .unavailable("Metrics API was not discovered for this cluster.")
            return
        }

        if !force {
            switch dashboardMetricsStateByQuery[query] {
            case .some(.loaded), .some(.loading), .some(.unavailable):
                return
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        dashboardMetricsTask?.cancel()
        dashboardMetricsStateByQuery[query] = .loading

        guard let metricsService else {
            dashboardMetricsStateByQuery[query] = .unavailable("Metrics service is unavailable.")
            return
        }

        let kubeconfig = loadedKubeconfig
        let namespace = namespaceForMetricsRequest(query)
        dashboardMetricsTask = Task.detached(priority: .utility) { [weak self, metricsService, kubeconfig, namespace, query] in
            do {
                let metrics = try await metricsService.dashboardMetrics(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    namespace: namespace
                )

                try Task.checkCancellation()
                await self?.finishDashboardMetrics(query: query, metrics: metrics)
            } catch is CancellationError {
                await self?.cancelDashboardMetrics(query: query)
            } catch let error as KubernetesClientError {
                await self?.failDashboardMetrics(query: query, error: error)
            } catch {
                await self?.failDashboardMetrics(query: query, error: error)
            }
        }
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

        resourceListTasksByQuery[query]?.cancel()
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
        resourceListTasksByQuery[query] = Task.detached(priority: .utility) { [weak self, resourceListService, kubeconfig, namespace, query] in
            do {
                let response = try await resourceListService.listResources(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: query.resource,
                    namespace: namespace
                )

                try Task.checkCancellation()
                await self?.finishResourceList(query: query, response: response)
            } catch is CancellationError {
                await self?.cancelResourceList(query: query)
            } catch {
                await self?.failResourceList(query: query, error: error)
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
        resourceDetailTask = Task.detached(priority: .utility) { [weak self, resourceDetailService, kubeconfig, query] in
            do {
                let detail = try await resourceDetailService.resourceDetail(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: query.resource,
                    namespace: query.namespace,
                    name: query.name
                )

                try Task.checkCancellation()
                await self?.finishResourceDetail(query: query, detail: detail)
            } catch is CancellationError {
                await self?.cancelResourceDetail(query: query)
            } catch {
                await self?.failResourceDetail(query: query, error: error)
            }
        }
    }

    func resourceEventsState(for detail: ResourceDetailSnapshot) -> ResourceEventsLoadState {
        guard selectedConnectionState == .connected else {
            return .failed("Connect to a cluster before loading events.")
        }

        guard let query = resourceEventsQuery(for: detail) else {
            return .failed("Events are not discoverable for this resource on the selected cluster.")
        }

        return resourceEventsStateByQuery[query] ?? .idle
    }

    func resourceEventsTaskID(for detail: ResourceDetailSnapshot) -> String {
        resourceEventsQuery(for: detail)?.id ?? "\(detail.query.id)|events|\(selectedConnectionState.rawValue)"
    }

    func loadResourceEvents(for detail: ResourceDetailSnapshot, force: Bool = false) {
        guard selectedConnectionState == .connected,
              let query = resourceEventsQuery(for: detail),
              query.eventsResource.verbs.contains("list") else {
            return
        }

        if !force {
            switch resourceEventsStateByQuery[query] {
            case .some(.loaded), .some(.loading):
                return
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        resourceEventsTask?.cancel()
        resourceEventsStateByQuery[query] = .loading

        guard let resourceEventService else {
            failResourceEvents(query: query, error: KubernetesClientError.unavailable("Resource event service is unavailable."))
            return
        }

        let kubeconfig = loadedKubeconfig
        resourceEventsTask = Task.detached(priority: .utility) { [weak self, resourceEventService, kubeconfig, query] in
            do {
                let response = try await resourceEventService.resourceEvents(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    eventsResource: query.eventsResource,
                    namespace: query.namespace,
                    involvedKind: query.involvedKind,
                    involvedName: query.involvedName,
                    involvedUID: query.involvedUID
                )

                try Task.checkCancellation()
                await self?.finishResourceEvents(query: query, response: response)
            } catch is CancellationError {
                await self?.cancelResourceEvents(query: query)
            } catch {
                await self?.failResourceEvents(query: query, error: error)
            }
        }
    }

    func envSecretValueState(
        namespace: String?,
        secretName: String?,
        key: String?
    ) -> ResourceEnvSecretValueLoadState {
        guard let query = envSecretValueQuery(namespace: namespace, secretName: secretName, key: key) else {
            return .idle
        }

        return envSecretValueStateByQuery[query] ?? .idle
    }

    func revealEnvSecretValue(
        namespace: String?,
        secretName: String?,
        key: String?,
        force: Bool = false
    ) {
        guard selectedConnectionState == .connected,
              let query = envSecretValueQuery(namespace: namespace, secretName: secretName, key: key) else {
            return
        }

        if !force {
            switch envSecretValueStateByQuery[query] {
            case .some(.loaded), .some(.loading):
                return
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        guard let secretResource = ResourceNavigationItem.secrets.discoveredResource(in: selectedDiscovery),
              secretResource.verbs.contains("get") else {
            envSecretValueStateByQuery[query] = .failed("Secrets are not discoverable for this cluster.")
            return
        }

        envSecretValueTasksByQuery[query]?.cancel()
        envSecretValueStateByQuery[query] = .loading

        guard let resourceDetailService else {
            failEnvSecretValue(query: query, message: "Resource detail service is unavailable.")
            return
        }

        let kubeconfig = loadedKubeconfig
        envSecretValueTasksByQuery[query] = Task.detached(priority: .utility) { [weak self, resourceDetailService, kubeconfig, secretResource, query] in
            do {
                let detail = try await resourceDetailService.resourceDetail(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: secretResource,
                    namespace: query.namespace,
                    name: query.secretName
                )

                try Task.checkCancellation()

                if let value = detail.decodedSecretValue(forKey: query.key) {
                    await self?.finishEnvSecretValue(query: query, value: value)
                } else {
                    await self?.failEnvSecretValue(query: query, message: "Secret key was not found.")
                }
            } catch is CancellationError {
                await self?.cancelEnvSecretValue(query: query)
            } catch {
                await self?.failEnvSecretValue(query: query, message: error.localizedDescription)
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

        if selectedClusterID == contextID, selectedResource == .dashboard {
            loadDashboardResources()
            loadDashboardMetrics()
        } else if selectedClusterID == contextID, let selectedResource {
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
        resourceEventsStateByQuery = resourceEventsStateByQuery.filter { $0.key.contextID != contextID }
        envSecretValueStateByQuery = envSecretValueStateByQuery.filter { $0.key.contextID != contextID }
        dashboardMetricsStateByQuery = dashboardMetricsStateByQuery.filter { $0.key.contextID != contextID }
    }

    private func finishResourceList(
        query: ResourceListQuery,
        response: KubernetesUnstructuredResourceList
    ) {
        resourceListTasksByQuery[query] = nil
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
        resourceListTasksByQuery[query] = nil
        if resourceListStateByQuery[query] == .loading {
            resourceListStateByQuery[query] = .idle
        }
    }

    private func failResourceList(query: ResourceListQuery, error: Error) {
        resourceListTasksByQuery[query] = nil
        resourceListStateByQuery[query] = .failed(error.localizedDescription)
    }

    private func finishDashboardMetrics(
        query: DashboardMetricsQuery,
        metrics: KubernetesDashboardMetrics
    ) {
        dashboardMetricsTask = nil
        dashboardMetricsStateByQuery[query] = .loaded(
            DashboardMetricsSnapshot(
                query: query,
                nodeMetrics: metrics.nodeMetrics,
                podMetrics: metrics.podMetrics,
                loadedAt: Date()
            )
        )
    }

    private func cancelDashboardMetrics(query: DashboardMetricsQuery) {
        dashboardMetricsTask = nil
        if dashboardMetricsStateByQuery[query] == .loading {
            dashboardMetricsStateByQuery[query] = .idle
        }
    }

    private func failDashboardMetrics(query: DashboardMetricsQuery, error: Error) {
        dashboardMetricsTask = nil
        if case KubernetesClientError.statusCode(404, _) = error {
            dashboardMetricsStateByQuery[query] = .unavailable("Metrics API is not installed on this cluster.")
        } else {
            dashboardMetricsStateByQuery[query] = .failed(error.localizedDescription)
        }
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

    private func finishResourceEvents(
        query: ResourceEventsQuery,
        response: KubernetesResourceEventList
    ) {
        resourceEventsStateByQuery[query] = .loaded(
            ResourceEventsSnapshot(
                query: query,
                events: response.summaries,
                resourceVersion: response.metadata?.resourceVersion,
                loadedAt: Date()
            )
        )
    }

    private func cancelResourceEvents(query: ResourceEventsQuery) {
        if resourceEventsStateByQuery[query] == .loading {
            resourceEventsStateByQuery[query] = .idle
        }
    }

    private func failResourceEvents(query: ResourceEventsQuery, error: Error) {
        resourceEventsStateByQuery[query] = .failed(error.localizedDescription)
    }

    private func finishEnvSecretValue(query: ResourceEnvSecretValueQuery, value: String) {
        envSecretValueTasksByQuery[query] = nil
        envSecretValueStateByQuery[query] = .loaded(value)
    }

    private func cancelEnvSecretValue(query: ResourceEnvSecretValueQuery) {
        envSecretValueTasksByQuery[query] = nil
        if envSecretValueStateByQuery[query] == .loading {
            envSecretValueStateByQuery[query] = .idle
        }
    }

    private func failEnvSecretValue(query: ResourceEnvSecretValueQuery, message: String) {
        envSecretValueTasksByQuery[query] = nil
        envSecretValueStateByQuery[query] = .failed(message)
    }

    private func cancelEnvSecretValueTasks() {
        envSecretValueTasksByQuery.values.forEach { $0.cancel() }
        envSecretValueTasksByQuery.removeAll()
    }

    private func cancelResourceListTasks() {
        resourceListTasksByQuery.values.forEach { $0.cancel() }
        resourceListTasksByQuery.removeAll()
    }

    private func cancelDashboardMetricsTask() {
        let query = dashboardMetricsQuery()
        dashboardMetricsTask?.cancel()
        dashboardMetricsTask = nil
        if let query, dashboardMetricsStateByQuery[query] == .loading {
            dashboardMetricsStateByQuery[query] = .idle
        }
    }

    private func navigate(
        clusterID: ClusterSummary.ID?,
        resource: ResourceNavigationItem,
        persist: Bool = true
    ) {
        route = AppRoute(clusterID: clusterID, resource: resource)

        if persist {
            userPreferences.selectedContextID = clusterID
            userPreferences.selectedResourceID = resource.rawValue
        }
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

    private func dashboardMetricsQuery() -> DashboardMetricsQuery? {
        guard let selectedClusterID else {
            return nil
        }

        return DashboardMetricsQuery(
            contextID: selectedClusterID,
            namespaceSelection: selectedNamespaceSelection
        )
    }

    private func dashboardResourceStates() -> [ResourceNavigationItem: ResourceListLoadState] {
        Dictionary(
            uniqueKeysWithValues: Self.dashboardResourceItems.map { item in
                (item, resourceListState(for: item))
            }
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

    private func resourceEventsQuery(for detail: ResourceDetailSnapshot) -> ResourceEventsQuery? {
        guard let selectedClusterID,
              selectedClusterID == detail.query.contextID,
              let eventsResource = ResourceNavigationItem.events.discoveredResource(in: selectedDiscovery) else {
            return nil
        }

        let involvedName = detail.summary.name ?? detail.query.name
        guard !involvedName.isEmpty else {
            return nil
        }

        let namespace = detail.summary.namespace ?? detail.query.namespace
        if eventsResource.namespaced, detail.query.resource.namespaced, namespace == nil {
            return nil
        }

        return ResourceEventsQuery(
            contextID: selectedClusterID,
            eventsResource: eventsResource,
            namespace: eventsResource.namespaced ? namespace : nil,
            involvedKind: detail.summary.kind ?? detail.query.resource.kind,
            involvedName: involvedName,
            involvedUID: detail.summary.uid
        )
    }

    private func namespaceForRequest(_ query: ResourceListQuery) -> String? {
        guard query.resource.namespaced,
              query.namespaceSelection != Self.allNamespacesSelection else {
            return nil
        }

        return query.namespaceSelection
    }

    private func namespaceForMetricsRequest(_ query: DashboardMetricsQuery) -> String? {
        query.namespaceSelection == Self.allNamespacesSelection ? nil : query.namespaceSelection
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

    private func envSecretValueQuery(
        namespace: String?,
        secretName: String?,
        key: String?
    ) -> ResourceEnvSecretValueQuery? {
        guard let selectedClusterID,
              let namespace,
              let secretName,
              let key,
              !namespace.isEmpty,
              !secretName.isEmpty,
              !key.isEmpty else {
            return nil
        }

        return ResourceEnvSecretValueQuery(
            contextID: selectedClusterID,
            namespace: namespace,
            secretName: secretName,
            key: key
        )
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }

    private static func initialClusterID(
        in clusters: [ClusterSummary],
        preferredClusterID: ClusterSummary.ID?
    ) -> ClusterSummary.ID? {
        if let preferredClusterID,
           clusters.contains(where: { $0.id == preferredClusterID }) {
            return preferredClusterID
        }

        return clusters.first(where: \.isCurrentContext)?.id ?? clusters.first?.id
    }

    private static func resourceNavigationItem(forID id: String?) -> ResourceNavigationItem? {
        guard let id else {
            return nil
        }

        return ResourceNavigationItem(rawValue: id)
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
        if resource.name == "nodes" {
            return try decodeList(
                """
                {
                  "apiVersion": "v1",
                  "kind": "NodeList",
                  "items": [
                    {
                      "apiVersion": "v1",
                      "kind": "Node",
                      "metadata": {
                        "name": "preview-node",
                        "uid": "preview-node"
                      },
                      "status": {
                        "allocatable": {
                          "cpu": "4",
                          "memory": "8Gi"
                        },
                        "conditions": [
                          {
                            "type": "Ready",
                            "status": "True"
                          }
                        ]
                      }
                    }
                  ]
                }
                """
            )
        }

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
                      "type": "Opaque",
                      "data": {
                        "db-password": "cHJldmlldy1wYXNzd29yZA=="
                      }
                    }
                    """.utf8
                )
            )
        }

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
                        "env": [
                          {
                            "name": "APP_ENV",
                            "value": "demo"
                          },
                          {
                            "name": "POD_NAME",
                            "valueFrom": {
                              "fieldRef": {
                                "fieldPath": "metadata.name"
                              }
                            }
                          },
                          {
                            "name": "DB_PASSWORD",
                            "valueFrom": {
                              "secretKeyRef": {
                                "name": "web-secrets",
                                "key": "db-password"
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
                              "name": "web-extra-secrets"
                            }
                          }
                        ],
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

private struct PreviewKubernetesMetricsService: KubernetesMetricsServicing {
    func dashboardMetrics(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String?
    ) async throws -> KubernetesDashboardMetrics {
        let nodeMetrics = try JSONDecoder().decode(
            KubernetesNodeMetricsList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": {
                        "name": "preview-node"
                      },
                      "timestamp": "2026-06-15T10:01:00Z",
                      "window": "30s",
                      "usage": {
                        "cpu": "740m",
                        "memory": "2450Mi"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
        let podMetrics = try JSONDecoder().decode(
            KubernetesPodMetricsList.self,
            from: Data(
                """
                {
                  "items": [
                    {
                      "metadata": {
                        "name": "web-0",
                        "namespace": "\(namespace ?? "vibekube-demo")"
                      },
                      "timestamp": "2026-06-15T10:01:00Z",
                      "window": "30s",
                      "containers": [
                        {
                          "name": "web",
                          "usage": {
                            "cpu": "120m",
                            "memory": "180Mi"
                          }
                        }
                      ]
                    }
                  ]
                }
                """.utf8
            )
        )

        return KubernetesDashboardMetrics(
            nodeMetrics: nodeMetrics.items,
            podMetrics: podMetrics.items
        )
    }
}

private struct PreviewKubernetesResourceEventService: KubernetesResourceEventServicing {
    func resourceEvents(
        contextName: String,
        kubeconfig: Kubeconfig,
        eventsResource: KubernetesDiscoveredResource,
        namespace: String?,
        involvedKind: String,
        involvedName: String,
        involvedUID: String?
    ) async throws -> KubernetesResourceEventList {
        try JSONDecoder().decode(
            KubernetesResourceEventList.self,
            from: Data(
                """
                {
                  "apiVersion": "\(eventsResource.groupVersion)",
                  "kind": "EventList",
                  "metadata": {
                    "resourceVersion": "421"
                  },
                  "items": [
                    {
                      "apiVersion": "\(eventsResource.groupVersion)",
                      "kind": "Event",
                      "metadata": {
                        "name": "\(involvedName).preview-scheduled",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "preview-event-scheduled",
                        "creationTimestamp": "2026-06-15T10:00:02Z"
                      },
                      "type": "Normal",
                      "reason": "Scheduled",
                      "note": "Successfully assigned \(namespace ?? "vibekube-demo")/\(involvedName) to preview-node",
                      "regarding": {
                        "kind": "\(involvedKind)",
                        "name": "\(involvedName)",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "\(involvedUID ?? "preview-pod-web-0")"
                      },
                      "reportingController": "default-scheduler",
                      "eventTime": "2026-06-15T10:00:02Z",
                      "deprecatedCount": 1
                    },
                    {
                      "apiVersion": "\(eventsResource.groupVersion)",
                      "kind": "Event",
                      "metadata": {
                        "name": "\(involvedName).preview-pulled",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "preview-event-pulled",
                        "creationTimestamp": "2026-06-15T10:00:07Z"
                      },
                      "type": "Normal",
                      "reason": "Pulled",
                      "note": "Container image already present on machine.",
                      "regarding": {
                        "kind": "\(involvedKind)",
                        "name": "\(involvedName)",
                        "namespace": "\(namespace ?? "vibekube-demo")",
                        "uid": "\(involvedUID ?? "preview-pod-web-0")",
                        "fieldPath": "spec.containers{web}"
                      },
                      "reportingController": "kubelet",
                      "reportingInstance": "preview-node",
                      "eventTime": "2026-06-15T10:00:07Z",
                      "deprecatedCount": 1
                    }
                  ]
                }
                """.utf8
            )
        )
    }
}
