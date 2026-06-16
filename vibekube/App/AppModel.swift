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
    @Published private(set) var podLogStateByQuery: [PodLogQuery: PodLogLoadState]
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var diagnosticsFileLoggingEnabled: Bool
    @Published private(set) var diagnosticsIncludeClusterNames: Bool
    @Published private(set) var diagnosticsRetentionDays: Int
    @Published private(set) var diagnosticsLogDirectoryPath: String
    @Published private var selectedNamespaceByContextID: [ClusterSummary.ID: String]

    private let kubeconfigLoader: KubeconfigLoader?
    private let connectionService: KubernetesConnectionServicing?
    private let resourceListService: KubernetesResourceListServicing?
    private let resourceDetailService: KubernetesResourceDetailServicing?
    private let resourceEventService: KubernetesResourceEventServicing?
    private let metricsService: KubernetesMetricsServicing?
    private let logService: KubernetesLogServicing?
    private let diagnosticsLogger: DiagnosticsLogger
    private var userPreferences: UserPreferencesProviding
    private var loadedKubeconfig: Kubeconfig
    private var connectionTask: Task<Void, Never>?
    private var resourceListTasksByQuery: [ResourceListQuery: Task<Void, Never>]
    private var resourceWatchTasksByQuery: [ResourceListQuery: Task<Void, Never>]
    private var resourceDetailTask: Task<Void, Never>?
    private var resourceEventsTask: Task<Void, Never>?
    private var dashboardMetricsTask: Task<Void, Never>?
    private var podLogTask: Task<Void, Never>?
    private var envSecretValueTasksByQuery: [ResourceEnvSecretValueQuery: Task<Void, Never>]
    private static let podLogLineLimit = 5_000

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
                logService: usePreviewData ? PreviewKubernetesLogService() : nil,
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
                logService: KubernetesLogService(execCredentialProvider: execCredentialProvider),
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
        logService: KubernetesLogServicing? = nil,
        userPreferences: UserPreferencesProviding? = nil,
        loadedKubeconfig: Kubeconfig? = nil,
        discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot] = [:],
        resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]? = nil,
        resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]? = nil,
        resourceEventsStateByQuery: [ResourceEventsQuery: ResourceEventsLoadState]? = nil,
        envSecretValueStateByQuery: [ResourceEnvSecretValueQuery: ResourceEnvSecretValueLoadState]? = nil,
        dashboardMetricsStateByQuery: [DashboardMetricsQuery: DashboardMetricsLoadState]? = nil,
        podLogStateByQuery: [PodLogQuery: PodLogLoadState]? = nil,
        diagnosticsLogger: DiagnosticsLogger = .shared,
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
        self.logService = logService
        self.diagnosticsLogger = diagnosticsLogger
        self.userPreferences = userPreferences
        self.loadedKubeconfig = loadedKubeconfig ?? .empty
        self.discoveryByContextID = discoveryByContextID
        self.resourceListStateByQuery = resourceListStateByQuery ?? [:]
        self.resourceDetailStateByQuery = resourceDetailStateByQuery ?? [:]
        self.resourceEventsStateByQuery = resourceEventsStateByQuery ?? [:]
        self.envSecretValueStateByQuery = envSecretValueStateByQuery ?? [:]
        self.dashboardMetricsStateByQuery = dashboardMetricsStateByQuery ?? [:]
        self.podLogStateByQuery = podLogStateByQuery ?? [:]
        self.diagnosticsFileLoggingEnabled = userPreferences.diagnosticsFileLoggingEnabled
        self.diagnosticsIncludeClusterNames = userPreferences.diagnosticsIncludeClusterNames
        self.diagnosticsRetentionDays = userPreferences.diagnosticsRetentionDays
        self.diagnosticsLogDirectoryPath = DiagnosticsLogger.defaultLogDirectoryURL().path
        self.selectedNamespaceByContextID = selectedNamespaceByContextID.isEmpty
            ? userPreferences.selectedNamespaceByContextID
            : selectedNamespaceByContextID
        self.resourceListTasksByQuery = [:]
        self.resourceWatchTasksByQuery = [:]
        self.resourceEventsTask = nil
        self.dashboardMetricsTask = nil
        self.podLogTask = nil
        self.envSecretValueTasksByQuery = [:]

        userPreferences.selectedContextID = initialClusterID
        userPreferences.selectedResourceID = initialResource.rawValue
        self.userPreferences = userPreferences
        configureDiagnostics()
        recordDiagnostic(.info, category: "app", message: "App model initialized.")
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

    private var appVersionDescription: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    func selectCluster(id: ClusterSummary.ID?) {
        guard route.clusterID != id else {
            return
        }

        connectionTask?.cancel()
        cancelResourceListTasks()
        cancelResourceWatchTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelPodLogTask()
        cancelEnvSecretValueTasks()
        navigate(clusterID: id, resource: .dashboard)
        connectionErrorMessage = nil
    }

    func selectResource(_ resource: ResourceNavigationItem) {
        guard route.resource != resource else {
            return
        }

        navigate(clusterID: selectedClusterID, resource: resource)
        cancelResourceWatchTasks()
        if resource == .dashboard {
            loadDashboardResources()
            loadDashboardMetrics()
        } else if resource == .logs {
            loadResourceList(for: .pods)
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
        cancelResourceWatchTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelPodLogTask()
        if selectedResource == .dashboard {
            loadDashboardResources(force: true)
            loadDashboardMetrics(force: true)
        } else if selectedResource == .logs {
            loadResourceList(for: .pods, force: true)
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

    func setDiagnosticsFileLoggingEnabled(_ enabled: Bool) {
        guard diagnosticsFileLoggingEnabled != enabled else {
            return
        }

        diagnosticsFileLoggingEnabled = enabled
        userPreferences.diagnosticsFileLoggingEnabled = enabled
        configureDiagnostics()
        recordDiagnostic(
            .info,
            category: "diagnostics",
            message: enabled ? "File diagnostics enabled." : "File diagnostics disabled."
        )
    }

    func setDiagnosticsIncludeClusterNames(_ enabled: Bool) {
        guard diagnosticsIncludeClusterNames != enabled else {
            return
        }

        diagnosticsIncludeClusterNames = enabled
        userPreferences.diagnosticsIncludeClusterNames = enabled
        configureDiagnostics()
        recordDiagnostic(
            .info,
            category: "diagnostics",
            message: enabled ? "Cluster names enabled for diagnostics." : "Cluster names disabled for diagnostics."
        )
    }

    func setDiagnosticsRetentionDays(_ days: Int) {
        let clampedDays = max(1, min(days, 30))
        guard diagnosticsRetentionDays != clampedDays else {
            return
        }

        diagnosticsRetentionDays = clampedDays
        userPreferences.diagnosticsRetentionDays = clampedDays
        configureDiagnostics()
        recordDiagnostic(
            .info,
            category: "diagnostics",
            message: "Diagnostics retention changed.",
            metadata: ["days": "\(clampedDays)"]
        )
    }

    func clearRecentDiagnostics() {
        Task { [diagnosticsLogger] in
            await diagnosticsLogger.clearRecentEvents()
        }
    }

    func diagnosticsExportText() async -> String {
        await diagnosticsLogger.exportText(
            appVersion: appVersionDescription,
            selectedContextID: selectedClusterID,
            selectedContextName: selectedCluster?.contextName,
            selectedConnectionState: selectedConnectionState.rawValue,
            selectedRoute: route.title,
            namespace: selectedNamespaceTitle,
            kubeconfigState: kubeconfigState.diagnosticsDescription
        )
    }

    func openLogsForSelectedRoute() {
        guard canOpenLogsForSelectedRoute else {
            return
        }

        selectResource(.logs)
    }

    func refresh() {
        cancelResourceWatchTasks()
        if selectedResource == .dashboard, selectedConnectionState == .connected {
            loadDashboardResources(force: true)
            loadDashboardMetrics(force: true)
        } else if selectedResource == .logs, selectedConnectionState == .connected {
            loadResourceList(for: .pods, force: true)
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

        recordDiagnostic(.info, category: "kubeconfig", message: "Reloading kubeconfig.")
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
        podLogStateByQuery = podLogStateByQuery.filter { validContextIDs.contains($0.key.contextID) }
        selectedNamespaceByContextID = selectedNamespaceByContextID.filter { validContextIDs.contains($0.key) }

        if discoveredClusters.isEmpty {
            navigate(clusterID: nil, resource: previousRoute.resource, persist: false)
            kubeconfigState = result.hasExistingSource
                ? .failed(message: result.issueSummary ?? "No contexts were found in kubeconfig.")
                : .missing(paths: result.requestedPaths.map(\.displayPath))
            recordDiagnostic(
                .warning,
                category: "kubeconfig",
                message: "No kubeconfig contexts loaded.",
                metadata: [
                    "sourceCount": "\(result.existingSources.count)",
                    "requestedPathCount": "\(result.requestedPaths.count)"
                ]
            )
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
        recordDiagnostic(
            .info,
            category: "kubeconfig",
            message: "Kubeconfig loaded.",
            metadata: [
                "contextCount": "\(discoveredClusters.count)",
                "sourceCount": "\(result.existingSources.count)"
            ]
        )
    }

    func connectSelectedCluster() {
        guard let selectedClusterID else { return }

        connectionTask?.cancel()
        cancelResourceListTasks()
        cancelResourceWatchTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelPodLogTask()
        cancelEnvSecretValueTasks()
        connectionErrorMessage = nil
        recordDiagnostic(
            .info,
            category: "connection",
            message: "Connecting to cluster.",
            contextID: selectedClusterID,
            metadata: clusterDiagnosticsMetadata(id: selectedClusterID)
        )

        guard let connectionService else {
            updateCluster(id: selectedClusterID) { cluster in
                cluster.connectionState = .connected
                cluster.lastSeenAt = Date()
            }
            discoveryByContextID[selectedClusterID] = .preview
            recordDiagnostic(
                .info,
                category: "connection",
                message: "Preview cluster connected.",
                contextID: selectedClusterID,
                metadata: clusterDiagnosticsMetadata(id: selectedClusterID)
            )
            if selectedResource == .dashboard {
                loadDashboardResources()
                loadDashboardMetrics()
            } else if selectedResource == .logs {
                loadResourceList(for: .pods)
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
        podLogStateByQuery = podLogStateByQuery.filter { $0.key.contextID != selectedClusterID }

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
        cancelResourceWatchTasks()
        resourceDetailTask?.cancel()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelPodLogTask()
        cancelEnvSecretValueTasks()
        connectionTask = nil
        resourceDetailTask = nil
        resourceEventsTask = nil
        dashboardMetricsTask = nil
        podLogTask = nil
        connectionErrorMessage = nil
        recordDiagnostic(
            .info,
            category: "connection",
            message: "Disconnecting cluster.",
            contextID: selectedClusterID,
            metadata: selectedClusterID.map { clusterDiagnosticsMetadata(id: $0) } ?? [:]
        )

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
            podLogStateByQuery = podLogStateByQuery.filter { $0.key.contextID != selectedClusterID }
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
            recordDiagnostic(
                .warning,
                category: "metrics",
                message: "Metrics API unavailable.",
                contextID: query.contextID,
                metadata: metricsDiagnosticsMetadata(query)
            )
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
        recordDiagnostic(
            .info,
            category: "metrics",
            message: "Loading dashboard metrics.",
            contextID: query.contextID,
            metadata: metricsDiagnosticsMetadata(query)
        )

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
            case .some(.loaded(let snapshot)):
                startResourceWatchIfNeeded(query: query, resourceVersion: snapshot.resourceVersion)
                return
            case .some(.loading(_)):
                return
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        resourceListTasksByQuery[query]?.cancel()
        resourceWatchTasksByQuery[query]?.cancel()
        resourceWatchTasksByQuery[query] = nil
        resourceListStateByQuery[query] = .loading(ResourceListLoadingProgress(query: query))
        recordDiagnostic(
            .info,
            category: "resourceList",
            message: "Loading resource list.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query)
        )

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
                let response: KubernetesUnstructuredResourceList
                if let progressService = resourceListService as? KubernetesResourceListProgressServicing {
                    response = try await progressService.listResources(
                        contextName: query.contextID,
                        kubeconfig: kubeconfig,
                        resource: query.resource,
                        namespace: namespace,
                        progress: { progress in
                            await self?.updateResourceListProgress(query: query, progress: progress)
                        }
                    )
                } else {
                    response = try await resourceListService.listResources(
                        contextName: query.contextID,
                        kubeconfig: kubeconfig,
                        resource: query.resource,
                        namespace: namespace
                    )
                }

                try Task.checkCancellation()
                await self?.finishResourceList(query: query, response: response)
            } catch is CancellationError {
                await self?.cancelResourceList(query: query)
            } catch {
                await self?.failResourceList(query: query, error: error)
            }
        }
    }

    func cancelResourceList(for resource: ResourceNavigationItem) {
        guard let query = resourceListQuery(for: resource) else {
            return
        }

        resourceListTasksByQuery[query]?.cancel()
        resourceListTasksByQuery[query] = nil
        if resourceListStateByQuery[query]?.isLoading == true {
            resourceListStateByQuery[query] = .idle
        }
        recordDiagnostic(
            .info,
            category: "resourceList",
            message: "Resource list cancelled.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query)
        )
    }

    func podLogState(
        for pod: KubernetesUnstructuredResource,
        containerName: String?,
        timestamps: Bool = true,
        previous: Bool = false,
        tailLines: Int? = 200,
        follow: Bool = false
    ) -> PodLogLoadState {
        guard let query = podLogQuery(
            for: pod,
            containerName: containerName,
            timestamps: timestamps,
            previous: previous,
            tailLines: tailLines,
            follow: follow
        ) else {
            return .idle
        }

        return podLogStateByQuery[query] ?? .idle
    }

    func podLogTaskID(
        for pod: KubernetesUnstructuredResource?,
        containerName: String?,
        timestamps: Bool = true,
        previous: Bool = false,
        tailLines: Int? = 200,
        follow: Bool = false
    ) -> String {
        guard let pod,
              let query = podLogQuery(
                for: pod,
                containerName: containerName,
                timestamps: timestamps,
                previous: previous,
                tailLines: tailLines,
                follow: follow
              ) else {
            return "\(selectedClusterID ?? "none")|logs|none|\(containerName ?? "")|\(timestamps)|\(previous)|\(tailLines.map(String.init) ?? "all")|\(follow)"
        }

        return query.id
    }

    func loadPodLogs(
        for pod: KubernetesUnstructuredResource,
        containerName: String?,
        timestamps: Bool = true,
        previous: Bool = false,
        tailLines: Int? = 200,
        follow: Bool = false,
        force: Bool = false
    ) {
        guard selectedConnectionState == .connected,
              let query = podLogQuery(
                for: pod,
                containerName: containerName,
                timestamps: timestamps,
                previous: previous,
                tailLines: tailLines,
                follow: follow
              ) else {
            return
        }

        if !force {
            switch podLogStateByQuery[query] {
            case .some(.loading):
                return
            case .some(.loaded) where !query.follow:
                return
            case .some(.loaded):
                break
            case .some(.idle), .some(.failed), .none:
                break
            }
        }

        podLogTask?.cancel()
        if query.follow {
            seedPodLogStream(query: query)
        } else {
            podLogStateByQuery[query] = .loading
        }
        recordDiagnostic(
            .info,
            category: "logs",
            message: query.follow ? "Starting pod log stream." : "Loading pod logs.",
            contextID: query.contextID,
            metadata: podLogDiagnosticsMetadata(query)
        )

        guard let logService else {
            finishPodLogs(query: query, text: PreviewKubernetesLogService.previewLogText)
            return
        }

        let kubeconfig = loadedKubeconfig
        let options = podLogOptions(for: query)

        podLogTask = Task.detached(priority: .utility) { [weak self, logService, kubeconfig, query, options] in
            do {
                if query.follow {
                    var receivedChunk = false
                    for try await chunk in logService.podLogStream(
                        contextName: query.contextID,
                        kubeconfig: kubeconfig,
                        namespace: query.namespace,
                        podName: query.podName,
                        options: options
                    ) {
                        try Task.checkCancellation()
                        receivedChunk = true
                        await self?.appendPodLogChunk(query: query, chunk: chunk)
                    }

                    try Task.checkCancellation()
                    await self?.finishPodLogStream(query: query, receivedChunk: receivedChunk)
                } else {
                    let text = try await logService.podLogs(
                        contextName: query.contextID,
                        kubeconfig: kubeconfig,
                        namespace: query.namespace,
                        podName: query.podName,
                        options: options
                    )

                    try Task.checkCancellation()
                    await self?.finishPodLogs(query: query, text: text)
                }
            } catch is CancellationError {
                await self?.cancelPodLogs(query: query)
            } catch {
                await self?.failPodLogs(query: query, error: error)
            }
        }
    }

    func stopPodLogs() {
        cancelPodLogTask()
    }

    func podLogsText(
        for pod: KubernetesUnstructuredResource,
        containerName: String?,
        timestamps: Bool = true,
        previous: Bool = false,
        tailLines: Int?
    ) async throws -> String {
        guard selectedConnectionState == .connected,
              let query = podLogQuery(
                for: pod,
                containerName: containerName,
                timestamps: timestamps,
                previous: previous,
                tailLines: tailLines,
                follow: false
              ) else {
            throw KubernetesClientError.unavailable("Connect to a cluster before loading pod logs.")
        }

        guard let logService else {
            return PreviewKubernetesLogService.previewLogText
        }

        return try await logService.podLogs(
            contextName: query.contextID,
            kubeconfig: loadedKubeconfig,
            namespace: query.namespace,
            podName: query.podName,
            options: podLogOptions(for: query)
        )
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
        recordDiagnostic(
            .info,
            category: "resourceDetail",
            message: "Loading resource detail.",
            contextID: query.contextID,
            metadata: resourceDetailDiagnosticsMetadata(query)
        )

        guard let resourceDetailService else {
            failResourceDetail(query: query, error: KubernetesClientError.unavailable("Resource detail service is unavailable."))
            return
        }

        let kubeconfig = loadedKubeconfig
        let configMapResource = ResourceNavigationItem.configMaps.discoveredResource(in: selectedDiscovery)
        let secretResource = ResourceNavigationItem.secrets.discoveredResource(in: selectedDiscovery)
        resourceDetailTask = Task.detached(priority: .utility) { [weak self, resourceDetailService, kubeconfig, query, configMapResource, secretResource] in
            do {
                let detail = try await resourceDetailService.resourceDetail(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: query.resource,
                    namespace: query.namespace,
                    name: query.name
                )
                let summary = await Self.expandedEnvironmentSummary(
                    for: detail,
                    query: query,
                    kubeconfig: kubeconfig,
                    resourceDetailService: resourceDetailService,
                    configMapResource: configMapResource,
                    secretResource: secretResource
                )

                try Task.checkCancellation()
                await self?.finishResourceDetail(query: query, detail: detail, summary: summary)
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
        recordDiagnostic(
            .info,
            category: "events",
            message: "Loading resource events.",
            contextID: query.contextID,
            metadata: resourceEventsDiagnosticsMetadata(query)
        )

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
        recordDiagnostic(
            .info,
            category: "secrets",
            message: "Revealing environment Secret value.",
            contextID: query.contextID,
            metadata: [
                "namespaceHash": DiagnosticsRedactor.hashIdentifier(query.namespace) ?? "-",
                "secretHash": DiagnosticsRedactor.hashIdentifier(query.secretName) ?? "-",
                "keyHash": DiagnosticsRedactor.hashIdentifier(query.key) ?? "-"
            ]
        )

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
        recordDiagnostic(
            .info,
            category: "connection",
            message: "Connection cancelled.",
            contextID: contextID,
            metadata: clusterDiagnosticsMetadata(id: contextID)
        )
    }

    private func finishConnection(contextID: ClusterSummary.ID, snapshot: KubernetesConnectionSnapshot) {
        updateCluster(id: contextID) { cluster in
            cluster.connectionState = .connected
            cluster.kubernetesVersion = snapshot.version.gitVersion
            cluster.lastSeenAt = Date()
        }
        discoveryByContextID[contextID] = snapshot.discovery
        recordDiagnostic(
            .info,
            category: "connection",
            message: "Cluster connected.",
            contextID: contextID,
            metadata: clusterDiagnosticsMetadata(id: contextID).merging([
                "kubernetesVersion": snapshot.version.gitVersion,
                "apiResourceCount": "\(snapshot.discovery.resourceCount)",
                "namespaceCount": "\(snapshot.discovery.namespaceDiscovery.items.count)"
            ]) { _, new in new }
        )

        if selectedNamespaceByContextID[contextID] == nil {
            selectedNamespaceByContextID[contextID] = Self.allNamespacesSelection
        }

        if selectedClusterID == contextID {
            connectionErrorMessage = nil
        }

        if selectedClusterID == contextID, selectedResource == .dashboard {
            loadDashboardResources()
            loadDashboardMetrics()
        } else if selectedClusterID == contextID, selectedResource == .logs {
            loadResourceList(for: .pods)
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
        recordDiagnostic(
            .error,
            category: "connection",
            message: "Cluster connection failed.",
            contextID: contextID,
            metadata: clusterDiagnosticsMetadata(id: contextID).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
        discoveryByContextID[contextID] = nil
        resourceListStateByQuery = resourceListStateByQuery.filter { $0.key.contextID != contextID }
        resourceDetailStateByQuery = resourceDetailStateByQuery.filter { $0.key.contextID != contextID }
        resourceEventsStateByQuery = resourceEventsStateByQuery.filter { $0.key.contextID != contextID }
        envSecretValueStateByQuery = envSecretValueStateByQuery.filter { $0.key.contextID != contextID }
        dashboardMetricsStateByQuery = dashboardMetricsStateByQuery.filter { $0.key.contextID != contextID }
        podLogStateByQuery = podLogStateByQuery.filter { $0.key.contextID != contextID }
    }

    private func finishResourceList(
        query: ResourceListQuery,
        response: KubernetesUnstructuredResourceList
    ) {
        resourceListTasksByQuery[query] = nil
        let items = response.items.map { normalizedResource($0, for: query) }
        resourceListStateByQuery[query] = .loaded(
            ResourceListSnapshot(
                query: query,
                items: items,
                resourceVersion: response.metadata?.resourceVersion,
                continueToken: response.metadata?.continueToken,
                loadedAt: Date()
            )
        )
        recordDiagnostic(
            .info,
            category: "resourceList",
            message: "Resource list loaded.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging([
                "itemCount": "\(items.count)",
                "hasContinueToken": response.metadata?.continueToken == nil ? "false" : "true"
            ]) { _, new in new }
        )
        startResourceWatchIfNeeded(query: query, resourceVersion: response.metadata?.resourceVersion)
    }

    private func updateResourceListProgress(
        query: ResourceListQuery,
        progress: ResourceListPageProgress
    ) {
        guard case .loading(let currentProgress) = resourceListStateByQuery[query] else {
            return
        }

        resourceListStateByQuery[query] = .loading(
            ResourceListLoadingProgress(
                query: query,
                startedAt: currentProgress.startedAt,
                itemCount: progress.itemCount,
                pageCount: progress.pageCount,
                remainingItemCount: progress.remainingItemCount
            )
        )
    }

    private func cancelResourceList(query: ResourceListQuery) {
        resourceListTasksByQuery[query] = nil
        if resourceListStateByQuery[query]?.isLoading == true {
            resourceListStateByQuery[query] = .idle
        }
    }

    private func failResourceList(query: ResourceListQuery, error: Error) {
        resourceListTasksByQuery[query] = nil
        resourceListStateByQuery[query] = .failed(error.localizedDescription)
        recordDiagnostic(
            .error,
            category: "resourceList",
            message: "Resource list failed.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func startResourceWatchIfNeeded(query: ResourceListQuery, resourceVersion: String?) {
        guard shouldWatchResourceList(query),
              resourceWatchTasksByQuery[query] == nil,
              let resourceListService else {
            return
        }

        let kubeconfig = loadedKubeconfig
        let namespace = namespaceForRequest(query)
        recordDiagnostic(
            .debug,
            category: "watch",
            message: "Starting resource watch.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query)
        )
        resourceWatchTasksByQuery[query] = Task.detached(priority: .utility) { [weak self, resourceListService, kubeconfig, namespace, query, resourceVersion] in
            do {
                for try await event in resourceListService.watchResources(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: query.resource,
                    namespace: namespace,
                    resourceVersion: resourceVersion
                ) {
                    try Task.checkCancellation()
                    await self?.applyResourceWatchEvent(event, query: query)
                }

                try Task.checkCancellation()
                await self?.finishResourceWatch(query: query)
            } catch is CancellationError {
                await self?.cancelResourceWatch(query: query)
            } catch {
                await self?.failResourceWatch(query: query, error: error)
            }
        }
    }

    private func applyResourceWatchEvent(
        _ event: KubernetesWatchEvent<KubernetesUnstructuredResource>,
        query: ResourceListQuery
    ) {
        guard case .loaded(var snapshot) = resourceListStateByQuery[query] else {
            return
        }

        switch event.type {
        case .added, .modified:
            guard let object = event.object else {
                return
            }
            let item = normalizedResource(object, for: query)
            if let index = snapshot.items.firstIndex(where: { $0.id == item.id }) {
                snapshot.items[index] = item
            } else {
                snapshot.items.append(item)
            }
            snapshot.resourceVersion = item.metadata.resourceVersion ?? snapshot.resourceVersion
            snapshot.loadedAt = Date()
        case .deleted:
            guard let object = event.object else {
                return
            }
            let item = normalizedResource(object, for: query)
            snapshot.items.removeAll { $0.id == item.id }
            snapshot.resourceVersion = item.metadata.resourceVersion ?? snapshot.resourceVersion
            snapshot.loadedAt = Date()
        case .bookmark:
            if let resourceVersion = event.object?.metadata.resourceVersion {
                snapshot.resourceVersion = resourceVersion
            }
            snapshot.loadedAt = Date()
        case .error:
            failResourceWatch(
                query: query,
                error: KubernetesClientError.statusCode(event.status?.code ?? 0, event.status?.message)
            )
            return
        }

        resourceListStateByQuery[query] = .loaded(snapshot)
    }

    private func finishResourceWatch(query: ResourceListQuery) {
        resourceWatchTasksByQuery[query] = nil
    }

    private func cancelResourceWatch(query: ResourceListQuery) {
        resourceWatchTasksByQuery[query] = nil
    }

    private func failResourceWatch(query: ResourceListQuery, error: Error) {
        resourceWatchTasksByQuery[query] = nil
        recordDiagnostic(
            .warning,
            category: "watch",
            message: "Resource watch failed.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func shouldWatchResourceList(_ query: ResourceListQuery) -> Bool {
        selectedClusterID == query.contextID &&
            selectedResource == .pods &&
            query.resource.name == "pods" &&
            query.resource.verbs.contains("watch")
    }

    private func normalizedResource(
        _ resource: KubernetesUnstructuredResource,
        for query: ResourceListQuery
    ) -> KubernetesUnstructuredResource {
        var item = resource
        if item.kind == nil {
            item.kind = query.resource.kind
        }
        if item.apiVersion == nil {
            item.apiVersion = query.resource.groupVersion
        }
        return item
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
        recordDiagnostic(
            .info,
            category: "metrics",
            message: "Dashboard metrics loaded.",
            contextID: query.contextID,
            metadata: metricsDiagnosticsMetadata(query).merging([
                "nodeMetricCount": "\(metrics.nodeMetrics.count)",
                "podMetricCount": "\(metrics.podMetrics.count)"
            ]) { _, new in new }
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
        recordDiagnostic(
            .warning,
            category: "metrics",
            message: "Dashboard metrics failed.",
            contextID: query.contextID,
            metadata: metricsDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func finishPodLogs(query: PodLogQuery, text: String) {
        podLogTask = nil
        podLogStateByQuery[query] = .loaded(
            PodLogSnapshot(
                query: query,
                text: Self.cappedPodLogText(text),
                loadedAt: Date()
            )
        )
        recordDiagnostic(
            .info,
            category: "logs",
            message: "Pod logs loaded.",
            contextID: query.contextID,
            metadata: podLogDiagnosticsMetadata(query).merging([
                "lineCount": "\(text.split(separator: "\n", omittingEmptySubsequences: false).count)"
            ]) { _, new in new }
        )
    }

    private func seedPodLogStream(query: PodLogQuery) {
        let tailQuery = PodLogQuery(
            contextID: query.contextID,
            namespace: query.namespace,
            podName: query.podName,
            containerName: query.containerName,
            previous: query.previous,
            tailLines: query.tailLines,
            timestamps: query.timestamps,
            follow: false
        )

        let seedText: String
        if case .loaded(let liveSnapshot) = podLogStateByQuery[query] {
            seedText = liveSnapshot.text
        } else if case .loaded(let tailSnapshot) = podLogStateByQuery[tailQuery] {
            seedText = tailSnapshot.text
        } else {
            seedText = ""
        }

        podLogStateByQuery[query] = .loaded(
            PodLogSnapshot(
                query: query,
                text: seedText,
                loadedAt: Date()
            )
        )
    }

    private func appendPodLogChunk(query: PodLogQuery, chunk: String) {
        let currentText: String
        if case .loaded(let snapshot) = podLogStateByQuery[query] {
            currentText = snapshot.text
        } else {
            currentText = ""
        }

        podLogStateByQuery[query] = .loaded(
            PodLogSnapshot(
                query: query,
                text: Self.cappedPodLogText(currentText + chunk),
                loadedAt: Date()
            )
        )
    }

    private func finishPodLogStream(query: PodLogQuery, receivedChunk: Bool) {
        podLogTask = nil
        if !receivedChunk, podLogStateByQuery[query] == .loading {
            finishPodLogs(query: query, text: "")
        }
        recordDiagnostic(
            .info,
            category: "logs",
            message: "Pod log stream ended.",
            contextID: query.contextID,
            metadata: podLogDiagnosticsMetadata(query).merging([
                "receivedChunk": receivedChunk ? "true" : "false"
            ]) { _, new in new }
        )
    }

    private func cancelPodLogs(query: PodLogQuery) {
        podLogTask = nil
        if podLogStateByQuery[query] == .loading {
            podLogStateByQuery[query] = .idle
        }
    }

    private func failPodLogs(query: PodLogQuery, error: Error) {
        podLogTask = nil
        podLogStateByQuery[query] = .failed(error.localizedDescription)
        recordDiagnostic(
            .error,
            category: "logs",
            message: "Pod logs failed.",
            contextID: query.contextID,
            metadata: podLogDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    nonisolated private static func expandedEnvironmentSummary(
        for detail: KubernetesResourceDetail,
        query: ResourceDetailQuery,
        kubeconfig: Kubeconfig,
        resourceDetailService: KubernetesResourceDetailServicing,
        configMapResource: KubernetesDiscoveredResource?,
        secretResource: KubernetesDiscoveredResource?
    ) async -> KubernetesResourceDetailSummary {
        var summary = detail.summary
        guard summary.kind == "Pod",
              !summary.environment.isEmpty,
              let namespace = summary.namespace ?? query.namespace else {
            return summary
        }

        var configMapCache: [String: [String: String]] = [:]
        var missingConfigMaps = Set<String>()
        var secretKeyCache: [String: [String]] = [:]
        var missingSecrets = Set<String>()

        func configMapValues(name: String) async -> [String: String]? {
            guard !missingConfigMaps.contains(name) else {
                return nil
            }
            if let cachedValues = configMapCache[name] {
                return cachedValues
            }
            guard let configMapResource, configMapResource.verbs.contains("get") else {
                missingConfigMaps.insert(name)
                return nil
            }

            do {
                let detail = try await resourceDetailService.resourceDetail(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: configMapResource,
                    namespace: namespace,
                    name: name
                )
                let values = detail.configMapValues
                configMapCache[name] = values
                return values
            } catch {
                missingConfigMaps.insert(name)
                return nil
            }
        }

        func secretKeys(name: String) async -> [String]? {
            guard !missingSecrets.contains(name) else {
                return nil
            }
            if let cachedKeys = secretKeyCache[name] {
                return cachedKeys
            }
            guard let secretResource, secretResource.verbs.contains("get") else {
                missingSecrets.insert(name)
                return nil
            }

            do {
                let detail = try await resourceDetailService.resourceDetail(
                    contextName: query.contextID,
                    kubeconfig: kubeconfig,
                    resource: secretResource,
                    namespace: namespace,
                    name: name
                )
                let keys = detail.secretKeys
                secretKeyCache[name] = keys
                return keys
            } catch {
                missingSecrets.insert(name)
                return nil
            }
        }

        var expandedContainers: [KubernetesContainerEnvironmentSummary] = []
        for container in summary.environment {
            var variables: [KubernetesEnvVarSummary] = []
            var indexByVariableName: [String: Int] = [:]
            var unresolvedEnvFrom: [KubernetesEnvFromSummary] = []

            func appendOrReplace(_ variable: KubernetesEnvVarSummary) {
                if let index = indexByVariableName[variable.name] {
                    variables[index] = variable
                } else {
                    indexByVariableName[variable.name] = variables.count
                    variables.append(variable)
                }
            }

            for source in container.envFrom {
                switch source.kind {
                case .configMapRef:
                    if let values = await configMapValues(name: source.name) {
                        for key in values.keys.sorted() {
                            let variableName = "\(source.prefix ?? "")\(key)"
                            guard isValidEnvironmentVariableName(variableName) else {
                                continue
                            }

                            appendOrReplace(KubernetesEnvVarSummary(
                                name: variableName,
                                literalValue: values[key],
                                source: KubernetesEnvVarSourceSummary(
                                    kind: .configMapKeyRef,
                                    name: source.name,
                                    key: key,
                                    fieldPath: nil,
                                    resource: nil,
                                    isOptional: source.isOptional
                                )
                            ))
                        }
                    } else {
                        unresolvedEnvFrom.append(source)
                    }
                case .secretRef:
                    if let keys = await secretKeys(name: source.name) {
                        for key in keys {
                            let variableName = "\(source.prefix ?? "")\(key)"
                            guard isValidEnvironmentVariableName(variableName) else {
                                continue
                            }

                            appendOrReplace(KubernetesEnvVarSummary(
                                name: variableName,
                                literalValue: nil,
                                source: KubernetesEnvVarSourceSummary(
                                    kind: .secretKeyRef,
                                    name: source.name,
                                    key: key,
                                    fieldPath: nil,
                                    resource: nil,
                                    isOptional: source.isOptional
                                )
                            ))
                        }
                    } else {
                        unresolvedEnvFrom.append(source)
                    }
                }
            }

            for variable in container.variables {
                appendOrReplace(await environmentVariableWithResolvedConfigMapValue(variable, configMapValues: configMapValues))
            }

            expandedContainers.append(
                KubernetesContainerEnvironmentSummary(
                    containerName: container.containerName,
                    variables: variables,
                    envFrom: unresolvedEnvFrom
                )
            )
        }

        summary.environment = expandedContainers
        return summary
    }

    nonisolated private static func environmentVariableWithResolvedConfigMapValue(
        _ variable: KubernetesEnvVarSummary,
        configMapValues: (String) async -> [String: String]?
    ) async -> KubernetesEnvVarSummary {
        guard let source = variable.source,
              source.kind == .configMapKeyRef,
              let name = source.name,
              let key = source.key,
              variable.literalValue == nil,
              let values = await configMapValues(name),
              let value = values[key] else {
            return variable
        }

        return KubernetesEnvVarSummary(
            name: variable.name,
            literalValue: value,
            source: source
        )
    }

    nonisolated private static func isValidEnvironmentVariableName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || (first >= "A" && first <= "Z") || (first >= "a" && first <= "z") else {
            return false
        }

        return value.unicodeScalars.dropFirst().allSatisfy { scalar in
            scalar == "_" || (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
        }
    }

    private func finishResourceDetail(
        query: ResourceDetailQuery,
        detail: KubernetesResourceDetail,
        summary: KubernetesResourceDetailSummary
    ) {
        resourceDetailStateByQuery[query] = .loaded(
            ResourceDetailSnapshot(
                query: query,
                yaml: detail.yaml,
                summary: summary,
                loadedAt: Date()
            )
        )
        recordDiagnostic(
            .info,
            category: "resourceDetail",
            message: "Resource detail loaded.",
            contextID: query.contextID,
            metadata: resourceDetailDiagnosticsMetadata(query).merging([
                "kind": summary.kind ?? query.resource.kind,
                "hasEnvironment": summary.environment.isEmpty ? "false" : "true"
            ]) { _, new in new }
        )
    }

    private func cancelResourceDetail(query: ResourceDetailQuery) {
        if resourceDetailStateByQuery[query] == .loading {
            resourceDetailStateByQuery[query] = .idle
        }
    }

    private func failResourceDetail(query: ResourceDetailQuery, error: Error) {
        resourceDetailStateByQuery[query] = .failed(error.localizedDescription)
        recordDiagnostic(
            .error,
            category: "resourceDetail",
            message: "Resource detail failed.",
            contextID: query.contextID,
            metadata: resourceDetailDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
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
        recordDiagnostic(
            .info,
            category: "events",
            message: "Resource events loaded.",
            contextID: query.contextID,
            metadata: resourceEventsDiagnosticsMetadata(query).merging([
                "eventCount": "\(response.summaries.count)"
            ]) { _, new in new }
        )
    }

    private func cancelResourceEvents(query: ResourceEventsQuery) {
        if resourceEventsStateByQuery[query] == .loading {
            resourceEventsStateByQuery[query] = .idle
        }
    }

    private func failResourceEvents(query: ResourceEventsQuery, error: Error) {
        resourceEventsStateByQuery[query] = .failed(error.localizedDescription)
        recordDiagnostic(
            .warning,
            category: "events",
            message: "Resource events failed.",
            contextID: query.contextID,
            metadata: resourceEventsDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func finishEnvSecretValue(query: ResourceEnvSecretValueQuery, value: String) {
        envSecretValueTasksByQuery[query] = nil
        envSecretValueStateByQuery[query] = .loaded(value)
        recordDiagnostic(
            .info,
            category: "secrets",
            message: "Environment Secret value revealed.",
            contextID: query.contextID,
            metadata: [
                "namespaceHash": DiagnosticsRedactor.hashIdentifier(query.namespace) ?? "-",
                "secretHash": DiagnosticsRedactor.hashIdentifier(query.secretName) ?? "-",
                "keyHash": DiagnosticsRedactor.hashIdentifier(query.key) ?? "-"
            ]
        )
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
        recordDiagnostic(
            .warning,
            category: "secrets",
            message: "Environment Secret value reveal failed.",
            contextID: query.contextID,
            metadata: [
                "namespaceHash": DiagnosticsRedactor.hashIdentifier(query.namespace) ?? "-",
                "secretHash": DiagnosticsRedactor.hashIdentifier(query.secretName) ?? "-",
                "keyHash": DiagnosticsRedactor.hashIdentifier(query.key) ?? "-",
                "error": message
            ]
        )
    }

    private func cancelEnvSecretValueTasks() {
        envSecretValueTasksByQuery.values.forEach { $0.cancel() }
        envSecretValueTasksByQuery.removeAll()
    }

    private func cancelResourceListTasks() {
        resourceListTasksByQuery.values.forEach { $0.cancel() }
        resourceListTasksByQuery.removeAll()
        for (query, state) in resourceListStateByQuery where state.isLoading {
            resourceListStateByQuery[query] = .idle
        }
    }

    private func cancelResourceWatchTasks() {
        resourceWatchTasksByQuery.values.forEach { $0.cancel() }
        resourceWatchTasksByQuery.removeAll()
    }

    private func cancelDashboardMetricsTask() {
        let query = dashboardMetricsQuery()
        dashboardMetricsTask?.cancel()
        dashboardMetricsTask = nil
        if let query, dashboardMetricsStateByQuery[query] == .loading {
            dashboardMetricsStateByQuery[query] = .idle
        }
    }

    private func cancelPodLogTask() {
        podLogTask?.cancel()
        podLogTask = nil
        for (query, state) in podLogStateByQuery where state == .loading {
            podLogStateByQuery[query] = .idle
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

    private func podLogQuery(
        for pod: KubernetesUnstructuredResource,
        containerName: String?,
        timestamps: Bool,
        previous: Bool,
        tailLines: Int?,
        follow: Bool
    ) -> PodLogQuery? {
        guard let selectedClusterID,
              let podName = pod.metadata.name,
              let namespace = pod.metadata.namespace,
              !podName.isEmpty,
              !namespace.isEmpty else {
            return nil
        }

        return PodLogQuery(
            contextID: selectedClusterID,
            namespace: namespace,
            podName: podName,
            containerName: containerName,
            previous: previous,
            tailLines: tailLines,
            timestamps: timestamps,
            follow: follow
        )
    }

    private func podLogOptions(for query: PodLogQuery) -> KubernetesPodLogOptions {
        KubernetesPodLogOptions(
            container: query.containerName,
            previous: query.previous,
            follow: query.follow,
            tailLines: query.follow ? 0 : query.tailLines,
            timestamps: query.timestamps
        )
    }

    private static func cappedPodLogText(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > podLogLineLimit else {
            return text
        }

        return lines.suffix(podLogLineLimit).joined(separator: "\n")
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

    private func configureDiagnostics() {
        let settings = DiagnosticsSettings(
            fileLoggingEnabled: diagnosticsFileLoggingEnabled,
            includeClusterNames: diagnosticsIncludeClusterNames,
            retentionDays: diagnosticsRetentionDays,
            maxTotalMegabytes: 50
        )

        Task { [diagnosticsLogger] in
            await diagnosticsLogger.configure(settings)
        }
    }

    private func recordDiagnostic(
        _ level: DiagnosticsLevel,
        category: String,
        message: String,
        contextID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let contextName = contextID.flatMap { id in
            clusters.first { $0.id == id }?.contextName
        }

        Task { [diagnosticsLogger] in
            await diagnosticsLogger.record(
                level,
                category: category,
                message: message,
                contextID: contextID,
                contextName: contextName,
                metadata: metadata
            )
        }
    }

    private func clusterDiagnosticsMetadata(id: ClusterSummary.ID) -> [String: String] {
        guard let cluster = clusters.first(where: { $0.id == id }) else {
            return [:]
        }

        let serverURL = URL(string: cluster.server)
        let serverHost = serverURL?.host ?? cluster.server
        return [
            "auth": cluster.authDescription,
            "serverScheme": serverURL?.scheme ?? "-",
            "serverHostHash": DiagnosticsRedactor.hashIdentifier(serverHost) ?? "-",
            "namespaceMode": cluster.namespace.isEmpty ? "none" : "context-default"
        ]
    }

    private func resourceListDiagnosticsMetadata(_ query: ResourceListQuery) -> [String: String] {
        [
            "resource": query.resource.name,
            "kind": query.resource.kind,
            "groupVersion": query.resource.groupVersion,
            "scope": query.resource.namespaced ? "namespaced" : "cluster",
            "namespace": namespaceDiagnosticsValue(query.namespaceSelection)
        ]
    }

    private func metricsDiagnosticsMetadata(_ query: DashboardMetricsQuery) -> [String: String] {
        [
            "namespace": namespaceDiagnosticsValue(query.namespaceSelection)
        ]
    }

    private func resourceDetailDiagnosticsMetadata(_ query: ResourceDetailQuery) -> [String: String] {
        [
            "resource": query.resource.name,
            "kind": query.resource.kind,
            "groupVersion": query.resource.groupVersion,
            "namespaceHash": DiagnosticsRedactor.hashIdentifier(query.namespace) ?? "-",
            "nameHash": DiagnosticsRedactor.hashIdentifier(query.name) ?? "-"
        ]
    }

    private func resourceEventsDiagnosticsMetadata(_ query: ResourceEventsQuery) -> [String: String] {
        [
            "resourceKind": query.involvedKind,
            "resourceNamespaceHash": DiagnosticsRedactor.hashIdentifier(query.namespace) ?? "-",
            "resourceNameHash": DiagnosticsRedactor.hashIdentifier(query.involvedName) ?? "-",
            "resourceUIDHash": DiagnosticsRedactor.hashIdentifier(query.involvedUID) ?? "-"
        ]
    }

    private func podLogDiagnosticsMetadata(_ query: PodLogQuery) -> [String: String] {
        [
            "namespaceHash": DiagnosticsRedactor.hashIdentifier(query.namespace) ?? "-",
            "podHash": DiagnosticsRedactor.hashIdentifier(query.podName) ?? "-",
            "containerHash": DiagnosticsRedactor.hashIdentifier(query.containerName) ?? "-",
            "previous": query.previous ? "true" : "false",
            "follow": query.follow ? "true" : "false",
            "timestamps": query.timestamps ? "true" : "false",
            "tailLines": query.tailLines.map(String.init) ?? "all"
        ]
    }

    private func errorDiagnosticsMetadata(_ error: Error) -> [String: String] {
        var metadata: [String: String] = [
            "errorType": String(describing: type(of: error)),
            "error": error.localizedDescription
        ]

        if let clientError = error as? KubernetesClientError {
            metadata["connectionState"] = clientError.connectionState.rawValue
        }

        return metadata
    }

    private func namespaceDiagnosticsValue(_ namespace: String) -> String {
        if namespace == Self.allNamespacesSelection {
            return "all"
        }

        return DiagnosticsRedactor.hashIdentifier(namespace) ?? "-"
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

        guard let item = ResourceNavigationItem(rawValue: id),
              item.isPrimaryNavigationVisible else {
            return nil
        }

        return item
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

private struct PreviewKubernetesLogService: KubernetesLogServicing {
    static let previewLogText = """
    2026-06-15T10:00:01Z web-0 starting preview server
    2026-06-15T10:00:03Z web-0 listening on :8080
    2026-06-15T10:00:07Z web-0 GET /healthz 200
    2026-06-15T10:00:12Z web-0 GET / 200
    """

    func podLogs(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) async throws -> String {
        Self.previewLogText
    }

    func podLogStream(
        contextName: String,
        kubeconfig: Kubeconfig,
        namespace: String,
        podName: String,
        options: KubernetesPodLogOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for line in Self.previewLogText.split(separator: "\n", omittingEmptySubsequences: false) {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(String(line) + "\n")
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
