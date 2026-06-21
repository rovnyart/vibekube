import Combine
import Foundation

private struct ResourceWatchEventBatch {
    var events: [KubernetesWatchEvent<KubernetesUnstructuredResource>] = []
    var lastEventAt: Date = Date()
}

private enum DebugActionFailureExplanation {
    enum Action {
        case exec
        case portForward
    }

    static func explain(_ message: String, action: Action) -> String {
        if let rbacExplanation = rbacExplanation(for: message, action: action) {
            return "\(rbacExplanation) \(message)"
        }

        if isStreamingProtocolFailure(message) {
            return "Streaming connection failed. Kubernetes \(action.name) requires an upgraded API connection; check that the API server or proxy supports WebSocket/SPDY upgrades. \(message)"
        }

        return message
    }

    private static func rbacExplanation(for message: String, action: Action) -> String? {
        let normalized = message.lowercased()
        guard normalized.contains("forbidden") else {
            return nil
        }

        switch action {
        case .exec:
            return "RBAC denied exec. Grant create on pods/exec in this namespace."
        case .portForward:
            return "RBAC denied port-forwarding. Grant create on pods/portforward in this namespace."
        }
    }

    private static func isStreamingProtocolFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("unable to upgrade connection") ||
            normalized.contains("error upgrading connection") ||
            normalized.contains("upgrade request required") ||
            normalized.contains("spdy") ||
            (normalized.contains("websocket") && normalized.contains("upgrade"))
    }
}

private struct MutationActionTarget {
    var service: KubernetesSafeMutationServicing
    var contextID: ClusterSummary.ID
    var kubeconfig: Kubeconfig
    var discoveredResource: KubernetesDiscoveredResource
    var namespace: String?
    var name: String
}

private struct ManifestMutationTarget {
    var service: KubernetesSafeMutationServicing
    var contextID: ClusterSummary.ID
    var kubeconfig: Kubeconfig
    var resource: KubernetesDiscoveredResource
    var namespace: String?
    var name: String
}

private extension DebugActionFailureExplanation.Action {
    var name: String {
        switch self {
        case .exec:
            "exec"
        case .portForward:
            "port-forward"
        }
    }
}

enum MutationPreviewRequestError: LocalizedError, Equatable {
    case unavailable
    case disconnected
    case missingCluster
    case missingResource
    case missingName

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Mutation preview is not available."
        case .disconnected:
            "Connect to the cluster before previewing changes."
        case .missingCluster:
            "No cluster is selected."
        case .missingResource:
            "The selected resource API is not available."
        case .missingName:
            "The selected row does not have a resource name."
        }
    }
}

enum MutationActionRequestError: LocalizedError, Equatable {
    case unavailable
    case disconnected
    case missingCluster
    case missingDiscovery
    case missingResource
    case missingName
    case unsupportedAction(String)
    case invalidManifestTarget

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Mutations are not available."
        case .disconnected:
            "Connect to the cluster before changing resources."
        case .missingCluster:
            "No cluster is selected."
        case .missingDiscovery:
            "Resource discovery is not loaded for the selected cluster."
        case .missingResource:
            "The selected resource API is not available."
        case .missingName:
            "The selected row does not have a resource name."
        case .unsupportedAction(let message):
            message
        case .invalidManifestTarget:
            "Could not match the YAML manifest to a discovered Kubernetes resource."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var clusters: [ClusterSummary]
    @Published private(set) var route: AppRoute
    @Published var searchText = ""
    @Published private(set) var kubeconfigState: KubeconfigDiscoveryState
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var connectionErrorMessage: String?
    @Published private(set) var connectionProgressMessage: String?
    @Published private(set) var discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot]
    @Published private(set) var resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]
    @Published private(set) var resourceWatchStatusByQuery: [ResourceListQuery: ResourceWatchStatus]
    @Published private(set) var resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]
    @Published private(set) var resourceEventsStateByQuery: [ResourceEventsQuery: ResourceEventsLoadState]
    @Published private(set) var envSecretValueStateByQuery: [ResourceEnvSecretValueQuery: ResourceEnvSecretValueLoadState]
    @Published private(set) var dashboardMetricsStateByQuery: [DashboardMetricsQuery: DashboardMetricsLoadState]
    @Published private(set) var podLogStateByQuery: [PodLogQuery: PodLogLoadState]
    @Published private(set) var portForwardSessions: [PortForwardSession]
    @Published private(set) var execLaunches: [ExecLaunchRecord]
    @Published private(set) var execLaunchErrorMessage: String?
    @Published private(set) var mutationActionHistory: [MutationActionRecord]
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var diagnosticsFileLoggingEnabled: Bool
    @Published private(set) var diagnosticsIncludeClusterNames: Bool
    @Published private(set) var diagnosticsRetentionDays: Int
    @Published private(set) var diagnosticsLogDirectoryPath: String
    @Published private(set) var podLogLineLimit: Int
    @Published private(set) var secretRevealRequiresConfirmation: Bool
    @Published private(set) var defaultNamespaceBehavior: DefaultNamespaceBehavior
    @Published private(set) var resourceWatchesEnabled: Bool
    @Published private(set) var kubeconfigPathOverride: String?
    @Published private(set) var tableDensity: TableDensity
    @Published private(set) var appAppearance: AppAppearance
    @Published private(set) var externalTerminalApp: ExternalTerminalApp
    @Published private(set) var aiProviderSettings: AIProviderSettings
    @Published private(set) var aiProviderSecrets: AIProviderSecrets
    @Published private(set) var aiModelDiscoveryState: AIModelDiscoveryState
    @Published private(set) var aiAvailabilityState: AIAvailabilityState
    @Published private(set) var resourceLabelFilter: ResourceLabelFilter?
    @Published private(set) var resourceOwnerFilter: ResourceOwnerFilter?
    @Published private(set) var resourceNameFilter: ResourceNameFilter?
    @Published private var selectedNamespaceByContextID: [ClusterSummary.ID: String]

    private var kubeconfigLoader: KubeconfigLoader?
    private let connectionService: KubernetesConnectionServicing?
    private let resourceListService: KubernetesResourceListServicing?
    private let resourceDetailService: KubernetesResourceDetailServicing?
    private let resourceEventService: KubernetesResourceEventServicing?
    private let mutationPreviewService: KubernetesMutationPreviewServicing?
    private let mutationActionService: KubernetesSafeMutationServicing?
    private let metricsService: KubernetesMetricsServicing?
    private let logService: KubernetesLogServicing?
    private let portForwardService: KubernetesPortForwardServicing?
    private let localPortChecker: LocalPortChecking
    private let execLauncher: KubernetesExecLaunching?
    private let aiProviderService: AIProviderServicing
    private let aiSecretStore: AISecretStoring
    private let diagnosticsLogger: DiagnosticsLogger
    private var userPreferences: UserPreferencesProviding
    private var loadedKubeconfig: Kubeconfig
    private var connectionTask: Task<Void, Never>?
    private var resourceListTasksByQuery: [ResourceListQuery: Task<Void, Never>]
    private var resourceWatchTasksByQuery: [ResourceListQuery: Task<Void, Never>]
    private var pendingResourceWatchBatchesByQuery: [ResourceListQuery: ResourceWatchEventBatch]
    private var resourceWatchFlushTasksByQuery: [ResourceListQuery: Task<Void, Never>]
    private var resourceDetailTask: Task<Void, Never>?
    private var resourceDetailWatchTasksByQuery: [ResourceDetailQuery: Task<Void, Never>]
    private var resourceEventsTask: Task<Void, Never>?
    private var dashboardMetricsTask: Task<Void, Never>?
    private var podLogTask: Task<Void, Never>?
    private var aiModelDiscoveryTask: Task<Void, Never>?
    private var aiAvailabilityTask: Task<Void, Never>?
    private var portForwardHandlesBySessionID: [PortForwardSession.ID: KubernetesPortForwardHandle]
    private var envSecretValueTasksByQuery: [ResourceEnvSecretValueQuery: Task<Void, Never>]
    nonisolated static let defaultPodLogLineLimit = 5_000
    private static let resourceWatchReconnectDelaysNanoseconds: [UInt64] = [
        500_000_000,
        1_000_000_000,
        2_000_000_000
    ]
    private static let resourceWatchFlushDelayNanoseconds: UInt64 = 150_000_000
    private static let aiSystemPrompt = """
    You are Vibekube's Kubernetes assistant. Use the provided Vibekube read-only tool results as evidence, especially logs and events. Explain what the selected Kubernetes context shows, distinguish observed facts from uncertainty, and suggest read-only next checks only when they add value. Do not claim you changed the cluster. Do not propose destructive actions unless the user explicitly asks, and even then present them as user-reviewed suggestions only.
    """

    nonisolated static let allNamespacesSelection = DashboardMetricsQuery.allNamespacesSelection
    nonisolated static let dashboardResourceItems: [ResourceNavigationItem] = [
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
                mutationPreviewService: nil,
                mutationActionService: nil,
                metricsService: usePreviewData ? PreviewKubernetesMetricsService() : nil,
                logService: usePreviewData ? PreviewKubernetesLogService() : nil,
                portForwardService: usePreviewData ? nil : KubectlPortForwardService(),
                execLauncher: usePreviewData ? nil : TerminalKubernetesExecLauncher(),
                aiProviderService: AIProviderClient(),
                aiSecretStore: InMemoryAISecretStore(),
                userPreferences: InMemoryUserPreferences()
            )
        } else {
            let execCredentialProvider = DefaultKubernetesExecCredentialProvider()
            self.init(
                clusters: [],
                kubeconfigState: .notLoaded,
                kubeconfigLoader: KubeconfigLoader(
                    environment: environment,
                    pathOverride: UserDefaultsUserPreferences().kubeconfigPathOverride
                ),
                connectionService: KubernetesConnectionService(execCredentialProvider: execCredentialProvider),
                resourceListService: KubernetesResourceListService(execCredentialProvider: execCredentialProvider),
                resourceDetailService: KubernetesResourceDetailService(execCredentialProvider: execCredentialProvider),
                resourceEventService: KubernetesResourceEventService(execCredentialProvider: execCredentialProvider),
                mutationPreviewService: KubernetesMutationPreviewService(
                    mutationService: KubernetesMutationService(execCredentialProvider: execCredentialProvider),
                    resourceDetailService: KubernetesResourceDetailService(execCredentialProvider: execCredentialProvider)
                ),
                mutationActionService: KubernetesSafeMutationService(
                    mutationService: KubernetesMutationService(execCredentialProvider: execCredentialProvider)
                ),
                metricsService: KubernetesMetricsService(execCredentialProvider: execCredentialProvider),
                logService: KubernetesLogService(execCredentialProvider: execCredentialProvider),
                portForwardService: KubectlPortForwardService(),
                execLauncher: TerminalKubernetesExecLauncher(),
                aiProviderService: AIProviderClient(),
                aiSecretStore: AIKeychainSecretStore(),
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
        mutationPreviewService: KubernetesMutationPreviewServicing? = nil,
        mutationActionService: KubernetesSafeMutationServicing? = nil,
        metricsService: KubernetesMetricsServicing? = nil,
        logService: KubernetesLogServicing? = nil,
        portForwardService: KubernetesPortForwardServicing? = nil,
        localPortChecker: LocalPortChecking = SocketLocalPortChecker(),
        execLauncher: KubernetesExecLaunching? = nil,
        aiProviderService: AIProviderServicing = AIProviderClient(),
        aiSecretStore: AISecretStoring = InMemoryAISecretStore(),
        userPreferences: UserPreferencesProviding? = nil,
        loadedKubeconfig: Kubeconfig? = nil,
        discoveryByContextID: [ClusterSummary.ID: KubernetesDiscoverySnapshot] = [:],
        resourceListStateByQuery: [ResourceListQuery: ResourceListLoadState]? = nil,
        resourceWatchStatusByQuery: [ResourceListQuery: ResourceWatchStatus]? = nil,
        resourceDetailStateByQuery: [ResourceDetailQuery: ResourceDetailLoadState]? = nil,
        resourceEventsStateByQuery: [ResourceEventsQuery: ResourceEventsLoadState]? = nil,
        envSecretValueStateByQuery: [ResourceEnvSecretValueQuery: ResourceEnvSecretValueLoadState]? = nil,
        dashboardMetricsStateByQuery: [DashboardMetricsQuery: DashboardMetricsLoadState]? = nil,
        podLogStateByQuery: [PodLogQuery: PodLogLoadState]? = nil,
        diagnosticsLogger: DiagnosticsLogger = .shared,
        podLogLineLimit: Int? = nil,
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
        self.kubeconfigLoader = kubeconfigLoader?.withPathOverride(userPreferences.kubeconfigPathOverride)
        self.connectionService = connectionService
        self.resourceListService = resourceListService
        self.resourceDetailService = resourceDetailService
        self.resourceEventService = resourceEventService
        self.mutationPreviewService = mutationPreviewService
        self.mutationActionService = mutationActionService
        self.metricsService = metricsService
        self.logService = logService
        self.portForwardService = portForwardService
        self.localPortChecker = localPortChecker
        self.execLauncher = execLauncher
        self.aiProviderService = aiProviderService
        self.aiSecretStore = aiSecretStore
        self.diagnosticsLogger = diagnosticsLogger
        self.userPreferences = userPreferences
        self.loadedKubeconfig = loadedKubeconfig ?? .empty
        self.discoveryByContextID = discoveryByContextID
        self.resourceListStateByQuery = resourceListStateByQuery ?? [:]
        self.resourceWatchStatusByQuery = resourceWatchStatusByQuery ?? [:]
        self.resourceDetailStateByQuery = resourceDetailStateByQuery ?? [:]
        self.resourceEventsStateByQuery = resourceEventsStateByQuery ?? [:]
        self.envSecretValueStateByQuery = envSecretValueStateByQuery ?? [:]
        self.dashboardMetricsStateByQuery = dashboardMetricsStateByQuery ?? [:]
        self.podLogStateByQuery = podLogStateByQuery ?? [:]
        self.portForwardSessions = []
        self.execLaunches = []
        self.execLaunchErrorMessage = nil
        self.mutationActionHistory = []
        self.connectionProgressMessage = nil
        self.diagnosticsFileLoggingEnabled = userPreferences.diagnosticsFileLoggingEnabled
        self.diagnosticsIncludeClusterNames = userPreferences.diagnosticsIncludeClusterNames
        self.diagnosticsRetentionDays = userPreferences.diagnosticsRetentionDays
        self.diagnosticsLogDirectoryPath = DiagnosticsLogger.defaultLogDirectoryURL().path
        self.podLogLineLimit = Self.clampedPodLogLineLimit(podLogLineLimit ?? userPreferences.podLogLineLimit)
        self.secretRevealRequiresConfirmation = userPreferences.secretRevealRequiresConfirmation
        self.defaultNamespaceBehavior = userPreferences.defaultNamespaceBehavior
        self.resourceWatchesEnabled = userPreferences.resourceWatchesEnabled
        self.kubeconfigPathOverride = userPreferences.kubeconfigPathOverride
        self.tableDensity = userPreferences.tableDensity
        self.appAppearance = userPreferences.appAppearance
        self.externalTerminalApp = userPreferences.externalTerminalApp
        self.aiProviderSettings = userPreferences.aiProviderSettings
        self.aiProviderSecrets = (try? aiSecretStore.loadSecrets()) ?? .empty
        self.aiModelDiscoveryState = .idle
        self.aiAvailabilityState = .unknown
        self.resourceLabelFilter = nil
        self.resourceOwnerFilter = nil
        self.resourceNameFilter = nil
        self.selectedNamespaceByContextID = selectedNamespaceByContextID.isEmpty
            ? userPreferences.selectedNamespaceByContextID
            : selectedNamespaceByContextID
        self.resourceListTasksByQuery = [:]
        self.resourceWatchTasksByQuery = [:]
        self.pendingResourceWatchBatchesByQuery = [:]
        self.resourceWatchFlushTasksByQuery = [:]
        self.resourceDetailWatchTasksByQuery = [:]
        self.resourceEventsTask = nil
        self.dashboardMetricsTask = nil
        self.podLogTask = nil
        self.aiModelDiscoveryTask = nil
        self.aiAvailabilityTask = nil
        self.portForwardHandlesBySessionID = [:]
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

        return defaultNamespaceSelection(for: selectedCluster)
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

    var selectedDashboardSnapshot: ClusterDashboardSnapshot {
        ClusterDashboardSnapshot.make(states: dashboardResourceStates())
    }

    var selectedDashboardResourceUsageSummary: DashboardResourceUsageSummary {
        DashboardResourceUsageSummary.make(
            state: dashboardMetricsState(),
            nodeItems: resourceListSnapshot(for: .nodes)?.items
        )
    }

    var canPreviewMutations: Bool {
        mutationPreviewService != nil && selectedConnectionState == .connected
    }

    var canApplyMutations: Bool {
        canPreviewMutations
    }

    var canRunMutations: Bool {
        mutationActionService != nil && selectedConnectionState == .connected
    }

    var aiIsConfigured: Bool {
        aiProviderSettings.isComplete && aiProviderSecrets.hasAPIKey
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
        cancelResourceDetailWatchTasks()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelPodLogTask()
        cancelEnvSecretValueTasks()
        navigate(clusterID: id, resource: .dashboard)
        connectionErrorMessage = nil
        connectionProgressMessage = nil
    }

    func selectResource(_ resource: ResourceNavigationItem) {
        guard route.resource != resource else {
            return
        }

        if resource != .pods {
            resourceLabelFilter = nil
        }
        if resourceOwnerFilter?.targetResource != resource {
            resourceOwnerFilter = nil
        }
        if resourceNameFilter?.targetResource != resource {
            resourceNameFilter = nil
        }
        navigate(clusterID: selectedClusterID, resource: resource)
        cancelResourceWatchTasks()
        cancelResourceDetailWatchTasks()
        if resource == .dashboard {
            loadDashboardResources()
            loadDashboardMetrics()
        } else {
            loadResourceList(for: resource)
        }
    }

    func navigateToOwnedResources(
        owner: KubernetesOwnerReferenceSummary,
        targetResource: ResourceNavigationItem,
        sourceTitle: String,
        namespace: String?
    ) {
        guard let selectedClusterID else {
            return
        }

        let previousResource = selectedResource
        let previousNamespaceSelection = selectedNamespaceSelection
        if let targetDiscovery = targetResource.discoveredResource(in: selectedDiscovery),
           targetDiscovery.namespaced,
           let namespace,
           !namespace.isEmpty,
           namespace != selectedNamespaceSelection {
            selectedNamespaceByContextID[selectedClusterID] = namespace
            userPreferences.selectedNamespaceByContextID = selectedNamespaceByContextID
        }

        searchText = ""
        resourceLabelFilter = nil
        resourceNameFilter = nil
        resourceOwnerFilter = ResourceOwnerFilter(
            sourceTitle: sourceTitle,
            owner: owner,
            targetResource: targetResource
        )

        if previousResource == targetResource {
            if previousNamespaceSelection != selectedNamespaceSelection {
                refreshSelectedNamespaceScope()
            } else {
                loadResourceList(for: targetResource, force: true)
            }
        } else {
            selectResource(targetResource)
        }
    }

    func navigateToPods(
        matching selector: KubernetesLabelSelectorSummary,
        sourceTitle: String,
        namespace: String?
    ) {
        guard let selectedClusterID else {
            return
        }

        let previousResource = selectedResource
        let previousNamespaceSelection = selectedNamespaceSelection
        if let podDiscovery = ResourceNavigationItem.pods.discoveredResource(in: selectedDiscovery),
           podDiscovery.namespaced,
           let namespace,
           !namespace.isEmpty,
           namespace != selectedNamespaceSelection {
            selectedNamespaceByContextID[selectedClusterID] = namespace
            userPreferences.selectedNamespaceByContextID = selectedNamespaceByContextID
        }

        searchText = ""
        resourceOwnerFilter = nil
        resourceNameFilter = nil
        resourceLabelFilter = ResourceLabelFilter(sourceTitle: sourceTitle, selector: selector)

        if previousResource == .pods {
            if previousNamespaceSelection != selectedNamespaceSelection {
                refreshSelectedNamespaceScope()
            } else {
                loadResourceList(for: .pods, force: true)
            }
        } else {
            selectResource(.pods)
        }
    }

    func navigateToResource(
        _ targetResource: ResourceNavigationItem,
        name: String,
        namespace: String?,
        sourceTitle: String
    ) {
        guard let selectedClusterID else {
            return
        }

        searchText = ""
        resourceLabelFilter = nil
        resourceOwnerFilter = nil
        resourceNameFilter = ResourceNameFilter(
            sourceTitle: sourceTitle,
            targetResource: targetResource,
            name: name
        )
        let previousResource = selectedResource
        let previousNamespaceSelection = selectedNamespaceSelection
        if let targetDiscovery = targetResource.discoveredResource(in: selectedDiscovery),
           targetDiscovery.namespaced,
           let namespace,
           !namespace.isEmpty,
           namespace != selectedNamespaceSelection {
            selectedNamespaceByContextID[selectedClusterID] = namespace
            userPreferences.selectedNamespaceByContextID = selectedNamespaceByContextID
        }

        if previousResource == targetResource {
            if previousNamespaceSelection != selectedNamespaceSelection {
                refreshSelectedNamespaceScope()
            } else {
                loadResourceList(for: targetResource, force: true)
            }
        } else {
            selectResource(targetResource)
        }
    }

    func navigateToOwner(_ owner: KubernetesOwnerReferenceSummary, namespace: String?) {
        guard let targetResource = ResourceNavigationItem.navigationItem(forOwnerKind: owner.kind),
              let selectedClusterID else {
            return
        }

        searchText = ""
        resourceLabelFilter = nil
        resourceOwnerFilter = nil
        resourceNameFilter = ResourceNameFilter(
            sourceTitle: "\(owner.kind)/\(owner.name)",
            targetResource: targetResource,
            name: owner.name
        )
        let previousResource = selectedResource
        let previousNamespaceSelection = selectedNamespaceSelection
        if let targetDiscovery = targetResource.discoveredResource(in: selectedDiscovery),
           targetDiscovery.namespaced,
           let namespace,
           !namespace.isEmpty,
           namespace != selectedNamespaceSelection {
            selectedNamespaceByContextID[selectedClusterID] = namespace
            userPreferences.selectedNamespaceByContextID = selectedNamespaceByContextID
        }

        if previousResource == targetResource {
            if previousNamespaceSelection != selectedNamespaceSelection {
                refreshSelectedNamespaceScope()
            } else {
                loadResourceList(for: targetResource, force: true)
            }
        } else {
            selectResource(targetResource)
        }
    }

    func selectNamespace(_ namespace: String) {
        guard let selectedClusterID else {
            return
        }

        selectedNamespaceByContextID[selectedClusterID] = namespace
        userPreferences.selectedNamespaceByContextID = selectedNamespaceByContextID
        refreshSelectedNamespaceScope()
    }

    private func refreshSelectedNamespaceScope() {
        cancelResourceWatchTasks()
        resourceDetailTask?.cancel()
        cancelResourceDetailWatchTasks()
        resourceEventsTask?.cancel()
        cancelPodLogTask()
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

    private func defaultNamespaceSelection(for cluster: ClusterSummary?) -> String {
        switch defaultNamespaceBehavior {
        case .allNamespaces:
            return Self.allNamespacesSelection
        case .contextNamespace:
            guard let namespace = cluster?.namespace,
                  !namespace.isEmpty else {
                return Self.allNamespacesSelection
            }
            return namespace
        }
    }

    func focusSearchField() {
        searchFocusRequestID += 1
    }

    func clearSearch() {
        searchText = ""
        resourceLabelFilter = nil
        resourceOwnerFilter = nil
        resourceNameFilter = nil
    }

    func clearResourceLabelFilter() {
        resourceLabelFilter = nil
    }

    func clearResourceOwnerFilter() {
        resourceOwnerFilter = nil
    }

    func clearResourceNameFilter() {
        resourceNameFilter = nil
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

    func setPodLogLineLimit(_ lineLimit: Int) {
        let clampedLimit = Self.clampedPodLogLineLimit(lineLimit)
        guard podLogLineLimit != clampedLimit else {
            return
        }

        podLogLineLimit = clampedLimit
        userPreferences.podLogLineLimit = clampedLimit
        recapLoadedPodLogs(lineLimit: clampedLimit)
        recordDiagnostic(
            .info,
            category: "settings",
            message: "Pod log buffer limit changed.",
            metadata: ["lineLimit": "\(clampedLimit)"]
        )
    }

    func setSecretRevealRequiresConfirmation(_ requiresConfirmation: Bool) {
        guard secretRevealRequiresConfirmation != requiresConfirmation else {
            return
        }

        secretRevealRequiresConfirmation = requiresConfirmation
        userPreferences.secretRevealRequiresConfirmation = requiresConfirmation
        recordDiagnostic(
            .info,
            category: "settings",
            message: "Secret reveal confirmation setting changed.",
            metadata: ["requiresConfirmation": requiresConfirmation ? "true" : "false"]
        )
    }

    func setDefaultNamespaceBehavior(_ behavior: DefaultNamespaceBehavior) {
        guard defaultNamespaceBehavior != behavior else {
            return
        }

        defaultNamespaceBehavior = behavior
        userPreferences.defaultNamespaceBehavior = behavior
        recordDiagnostic(
            .info,
            category: "settings",
            message: "Default namespace behavior changed.",
            metadata: ["behavior": behavior.rawValue]
        )
        refreshSelectedNamespaceScope()
    }

    func setResourceWatchesEnabled(_ enabled: Bool) {
        guard resourceWatchesEnabled != enabled else {
            return
        }

        resourceWatchesEnabled = enabled
        userPreferences.resourceWatchesEnabled = enabled
        recordDiagnostic(
            .info,
            category: "settings",
            message: enabled ? "Resource watches enabled." : "Resource watches disabled.",
            metadata: ["enabled": enabled ? "true" : "false"]
        )

        if enabled {
            startActiveResourceWatchIfPossible()
        } else {
            cancelResourceWatchTasks()
            cancelResourceDetailWatchTasks()
        }
    }

    func setKubeconfigPathOverride(_ pathOverride: String?) {
        let normalized = Self.normalizedKubeconfigPathOverride(pathOverride)
        guard kubeconfigPathOverride != normalized else {
            return
        }

        kubeconfigPathOverride = normalized
        userPreferences.kubeconfigPathOverride = normalized
        kubeconfigLoader = kubeconfigLoader?.withPathOverride(normalized)
        recordDiagnostic(
            .info,
            category: "settings",
            message: normalized == nil ? "Kubeconfig path reset to default discovery." : "Kubeconfig path override changed.",
            metadata: ["customPath": normalized == nil ? "false" : "true"]
        )
        reloadKubeconfig()
    }

    func setTableDensity(_ density: TableDensity) {
        guard tableDensity != density else {
            return
        }

        tableDensity = density
        userPreferences.tableDensity = density
        recordDiagnostic(
            .info,
            category: "settings",
            message: "Table density changed.",
            metadata: ["density": density.rawValue]
        )
    }

    func setAppAppearance(_ appearance: AppAppearance) {
        guard appAppearance != appearance else {
            return
        }

        appAppearance = appearance
        userPreferences.appAppearance = appearance
        recordDiagnostic(
            .info,
            category: "settings",
            message: "App appearance changed.",
            metadata: ["appearance": appearance.rawValue]
        )
    }

    func setExternalTerminalApp(_ terminalApp: ExternalTerminalApp) {
        guard externalTerminalApp != terminalApp else {
            return
        }

        externalTerminalApp = terminalApp
        userPreferences.externalTerminalApp = terminalApp
        recordDiagnostic(
            .info,
            category: "settings",
            message: "External terminal app changed.",
            metadata: ["terminalApp": terminalApp.rawValue]
        )
    }

    func setAIProviderShape(_ shape: AIProviderShape) {
        guard aiProviderSettings.shape != shape else {
            return
        }

        var settings = aiProviderSettings
        settings.shape = shape
        settings.preset = shape == .anthropicCompatible ? .anthropic : .custom
        settings.baseURLString = settings.preset.defaultBaseURLString
        settings.selectedModelID = nil
        saveAIProviderSettings(settings, reason: "AI provider shape changed.")
    }

    func setAIProviderPreset(_ preset: AIProviderPreset) {
        guard aiProviderSettings.preset != preset else {
            return
        }

        var settings = aiProviderSettings
        settings.preset = preset
        if preset != .custom {
            settings.shape = preset.shape
        }
        if preset != .custom {
            settings.baseURLString = preset.defaultBaseURLString
        }
        settings.selectedModelID = nil
        saveAIProviderSettings(settings, reason: "AI provider preset changed.")
    }

    func setAIBaseURLString(_ baseURLString: String) {
        guard aiProviderSettings.baseURLString != baseURLString else {
            return
        }

        var settings = aiProviderSettings
        settings.baseURLString = baseURLString
        settings.preset = AIProviderPreset.allCases.first {
            $0.defaultBaseURLString == baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? .custom
        settings.selectedModelID = nil
        saveAIProviderSettings(settings, reason: "AI provider base URL changed.")
    }

    func setAISelectedModelID(_ modelID: String?) {
        let normalized = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModelID = normalized?.isEmpty == false ? normalized : nil
        guard aiProviderSettings.selectedModelID != selectedModelID else {
            return
        }

        var settings = aiProviderSettings
        settings.selectedModelID = selectedModelID
        saveAIProviderSettings(settings, reason: "AI model selection changed.", resetAvailability: false)
    }

    func saveAIProviderSecrets(apiKey: String, headers: [AISecretHeader]) {
        let secrets = AIProviderSecrets(apiKey: apiKey, headers: headers)
        do {
            try aiSecretStore.saveSecrets(secrets)
            aiProviderSecrets = secrets
            invalidateAIProviderReachability()
            recordDiagnostic(
                .info,
                category: "ai",
                message: "AI provider secrets saved.",
                metadata: ["customHeaderCount": "\(secrets.usableHeaders.count)"]
            )
        } catch {
            aiAvailabilityState = .unavailable(error.localizedDescription)
            recordDiagnostic(
                .error,
                category: "ai",
                message: "Failed to save AI provider secrets.",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func clearAIProviderSecrets() {
        do {
            try aiSecretStore.deleteSecrets()
            aiProviderSecrets = .empty
            invalidateAIProviderReachability()
            recordDiagnostic(.info, category: "ai", message: "AI provider secrets cleared.")
        } catch {
            aiAvailabilityState = .unavailable(error.localizedDescription)
            recordDiagnostic(
                .error,
                category: "ai",
                message: "Failed to clear AI provider secrets.",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func fetchAIModels() {
        aiModelDiscoveryTask?.cancel()
        aiAvailabilityTask?.cancel()
        aiModelDiscoveryState = .loading
        aiAvailabilityState = .checking

        let settings = aiProviderSettings
        let secrets = aiProviderSecrets
        aiModelDiscoveryTask = Task { [weak self, aiProviderService] in
            do {
                let models = try await aiProviderService.listModels(settings: settings, secrets: secrets)
                self?.finishAIModelDiscovery(models)
            } catch is CancellationError {
                self?.cancelAIModelDiscovery()
            } catch {
                self?.failAIModelDiscovery(error)
            }
        }
    }

    func testAIProviderAvailability() {
        aiAvailabilityTask?.cancel()
        aiAvailabilityState = .checking

        let settings = aiProviderSettings
        let secrets = aiProviderSecrets
        aiAvailabilityTask = Task { [weak self, aiProviderService] in
            do {
                let message = try await aiProviderService.testConnection(settings: settings, secrets: secrets)
                self?.finishAIAvailability(message)
            } catch is CancellationError {
                self?.cancelAIAvailability()
            } catch {
                self?.failAIAvailability(error)
            }
        }
    }

    func aiContextBundle(for detail: ResourceDetailSnapshot) -> AIContextBundle {
        AIContextBuilder.resourceContext(
            detail: detail,
            cluster: selectedCluster,
            namespaceTitle: selectedNamespaceTitle,
            eventState: resourceEventsState(for: detail),
            logSnapshots: aiLogSnapshots(for: detail)
        )
    }

    func gatherAIContext(for detail: ResourceDetailSnapshot, userPrompt: String) async -> AIContextGatherResult {
        var toolNotes = ["Read selected resource manifest, status, conditions, relationships, and redacted environment from Vibekube."]
        var eventState = resourceEventsState(for: detail)
        var logSnapshots = aiLogSnapshots(for: detail)
        let relatedPodResult = await gatherAIRelatedPodContext(for: detail, userPrompt: userPrompt)
        let relatedPodContext = relatedPodResult.context
        toolNotes.append(contentsOf: relatedPodResult.notes)
        if let relatedPodContext {
            logSnapshots = mergedLogSnapshots(logSnapshots + relatedPodContext.logSnapshots)
        }

        let eventResult = await gatherAIResourceEvents(for: detail)
        eventState = eventResult.state
        toolNotes.append(contentsOf: eventResult.notes)

        if shouldGatherPodLogs(for: detail, userPrompt: userPrompt) {
            let logResult = await gatherAIPodLogs(for: detail, userPrompt: userPrompt)
            logSnapshots = mergedLogSnapshots(logSnapshots + logResult.snapshots)
            toolNotes.append(contentsOf: logResult.notes)
        } else if detail.summary.kind == "Pod" || detail.query.resource.kind == "Pod" {
            toolNotes.append("Skipped pod log reads because the prompt did not ask for runtime/log investigation.")
        }

        var context = AIContextBuilder.resourceContext(
            detail: detail,
            cluster: selectedCluster,
            namespaceTitle: selectedNamespaceTitle,
            eventState: eventState,
            logSnapshots: logSnapshots
        )

        let toolSummary = toolNotes.map { "- \($0)" }.joined(separator: "\n")
        context.sections.insert(
            AIContextSection(
                id: "vibekube-read-only-tools",
                title: "Vibekube Read-Only Tools",
                content: toolSummary
            ),
            at: 0
        )
        if let relatedPodContext {
            context.sections.insert(
                AIContextSection(
                    title: relatedPodContext.title,
                    content: relatedPodContext.content
                ),
                at: min(1, context.sections.count)
            )
        }

        return AIContextGatherResult(context: context, toolSummary: toolSummary)
    }

    func completeAIChat(context: AIContextBundle?, userPrompt: String) async throws -> AIChatResponse {
        guard aiIsConfigured else {
            throw AIProviderClientError.missingModel
        }

        let request = AIChatRequest(
            systemPrompt: Self.aiSystemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        return try await aiProviderService.complete(
            settings: aiProviderSettings,
            secrets: aiProviderSecrets,
            request: request
        )
    }

    func streamAIChat(context: AIContextBundle?, userPrompt: String) throws -> AsyncThrowingStream<AIChatStreamChunk, Error> {
        guard aiIsConfigured else {
            throw AIProviderClientError.missingModel
        }

        let request = AIChatRequest(
            systemPrompt: Self.aiSystemPrompt,
            userPrompt: userPrompt,
            context: context
        )

        return aiProviderService.streamComplete(
            settings: aiProviderSettings,
            secrets: aiProviderSecrets,
            request: request
        )
    }

    func resetLocalPreferences() {
        let previousKubeconfigPathOverride = kubeconfigPathOverride
        userPreferences.resetLocalPreferences()
        try? aiSecretStore.deleteSecrets()

        selectedNamespaceByContextID = userPreferences.selectedNamespaceByContextID
        diagnosticsFileLoggingEnabled = userPreferences.diagnosticsFileLoggingEnabled
        diagnosticsIncludeClusterNames = userPreferences.diagnosticsIncludeClusterNames
        diagnosticsRetentionDays = userPreferences.diagnosticsRetentionDays
        podLogLineLimit = Self.clampedPodLogLineLimit(userPreferences.podLogLineLimit)
        secretRevealRequiresConfirmation = userPreferences.secretRevealRequiresConfirmation
        defaultNamespaceBehavior = userPreferences.defaultNamespaceBehavior
        resourceWatchesEnabled = userPreferences.resourceWatchesEnabled
        kubeconfigPathOverride = userPreferences.kubeconfigPathOverride
        tableDensity = userPreferences.tableDensity
        appAppearance = userPreferences.appAppearance
        externalTerminalApp = userPreferences.externalTerminalApp
        aiProviderSettings = userPreferences.aiProviderSettings
        aiProviderSecrets = .empty
        invalidateAIProviderReachability()
        configureDiagnostics()

        cancelResourceWatchTasks()
        cancelResourceDetailWatchTasks()

        if previousKubeconfigPathOverride != kubeconfigPathOverride,
           kubeconfigLoader != nil {
            kubeconfigLoader = kubeconfigLoader?.withPathOverride(kubeconfigPathOverride)
            reloadKubeconfig()
        } else {
            navigate(
                clusterID: Self.initialClusterID(in: clusters, preferredClusterID: nil),
                resource: .dashboard
            )
            refreshSelectedNamespaceScope()
        }

        recordDiagnostic(
            .info,
            category: "settings",
            message: "Local preferences reset."
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

    func portForwardSession(for target: KubernetesPortForwardTargetSummary) -> PortForwardSession? {
        guard let selectedClusterID else {
            return nil
        }

        return portForwardSessions.first { session in
            session.matches(target: target, contextID: selectedClusterID)
        }
    }

    func startPortForward(target: KubernetesPortForwardTargetSummary) {
        guard let selectedClusterID,
              selectedConnectionState == .connected else {
            return
        }

        if portForwardSession(for: target)?.isActive == true {
            return
        }

        let sessionID = UUID()
        let session = PortForwardSession(
            id: sessionID,
            contextID: selectedClusterID,
            namespace: target.namespace,
            resourceKind: target.resourceKind,
            resourceName: target.resourceName,
            portName: target.portName,
            localPort: target.localPort,
            remotePort: target.remotePort,
            startedAt: Date(),
            status: .starting
        )
        portForwardSessions.insert(session, at: 0)

        guard let portForwardService else {
            failPortForwardSession(sessionID, message: "Port forwarding is not available in preview mode.")
            return
        }

        guard localPortChecker.isLocalPortAvailable(target.localPort) else {
            failPortForwardSession(
                sessionID,
                message: "Local port \(target.localPort) is already in use."
            )
            return
        }

        let request = KubernetesPortForwardRequest(
            contextName: selectedClusterID,
            namespace: target.namespace,
            resourceKind: target.resourceKind,
            resourceName: target.resourceName,
            localPort: target.localPort,
            remotePort: target.remotePort,
            kubeconfigPath: kubeconfigPath(forContextID: selectedClusterID)
        )

        Task { [weak self, portForwardService] in
            guard let model = self else {
                return
            }

            do {
                let handle = try await portForwardService.startPortForward(request: request) { [weak model] termination in
                    guard let model else {
                        return
                    }

                    Task { @MainActor [model] in
                        model.finishPortForwardSession(sessionID, termination: termination)
                    }
                }
                model.portForwardHandlesBySessionID[sessionID] = handle
                model.updatePortForwardSession(sessionID) { session in
                    session.status = .running(processIdentifier: handle.processIdentifier)
                }
            } catch {
                model.failPortForwardSession(sessionID, message: error.localizedDescription)
            }
        }
    }

    func stopPortForward(sessionID: PortForwardSession.ID) {
        portForwardHandlesBySessionID[sessionID]?.stop()
        updatePortForwardSession(sessionID) { session in
            session.status = .stopped
        }
    }

    func stopAllPortForwardSessions() {
        stopPortForwardSessions { _ in true }
    }

    func clearInactivePortForwardSessions() {
        let inactiveIDs = Set(portForwardSessions.filter { !$0.isActive }.map(\.id))
        portForwardSessions.removeAll { inactiveIDs.contains($0.id) }
    }

    func canOpenPodExec(for pod: KubernetesUnstructuredResource) -> Bool {
        selectedConnectionState == .connected &&
            pod.displayKind == "Pod" &&
            pod.metadata.name?.isEmpty == false &&
            pod.metadata.namespace?.isEmpty == false
    }

    func openPodExec(
        for pod: KubernetesUnstructuredResource,
        containerName: String? = nil,
        command: [String] = KubernetesExecCommandChoice.sh.command
    ) {
        guard let selectedClusterID,
              canOpenPodExec(for: pod),
              let namespace = pod.metadata.namespace,
              let podName = pod.metadata.name else {
            return
        }

        guard let execLauncher else {
            execLaunchErrorMessage = "Exec is not available in preview mode."
            return
        }

        let launchID = UUID()
        execLaunches.insert(
            ExecLaunchRecord(
                id: launchID,
                contextID: selectedClusterID,
                namespace: namespace,
                podName: podName,
                containerName: containerName,
                command: command,
                terminalApp: externalTerminalApp,
                launchedAt: Date(),
                status: .opening
            ),
            at: 0
        )

        let request = KubernetesExecLaunchRequest(
            contextName: selectedClusterID,
            namespace: namespace,
            podName: podName,
            containerName: containerName,
            command: command,
            kubeconfigPath: kubeconfigPath(forContextID: selectedClusterID),
            terminalApp: externalTerminalApp
        )

        Task { [weak self, execLauncher] in
            do {
                try await execLauncher.launchExec(request: request)
                self?.updateExecLaunch(launchID) { launch in
                    launch.status = .opened
                }
            } catch {
                let message = self?.explainedExecFailureMessage(error.localizedDescription) ?? error.localizedDescription
                self?.updateExecLaunch(launchID) { launch in
                    launch.status = .failed(message)
                }
                self?.execLaunchErrorMessage = message
            }
        }
    }

    func clearExecLaunchHistory() {
        execLaunches.removeAll()
    }

    func clearExecLaunchHistory(for pod: KubernetesUnstructuredResource) {
        guard let selectedClusterID,
              let namespace = pod.metadata.namespace,
              let podName = pod.metadata.name else {
            return
        }

        execLaunches.removeAll { launch in
            launch.contextID == selectedClusterID &&
                launch.namespace == namespace &&
                launch.podName == podName
        }
    }

    func clearExecLaunchError() {
        execLaunchErrorMessage = nil
    }

    func refresh() {
        cancelResourceWatchTasks()
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

        recordDiagnostic(.info, category: "kubeconfig", message: "Reloading kubeconfig.")
        let previousRoute = route
        let result = kubeconfigLoader.load()
        let discoveredClusters = result.kubeconfig.clusterSummaries()
        loadedKubeconfig = result.kubeconfig
        clusters = discoveredClusters
        connectionErrorMessage = nil
        connectionProgressMessage = nil
        let validContextIDs = Set(discoveredClusters.map(\.id))
        stopPortForwardSessions { !validContextIDs.contains($0.contextID) }
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

    private static func normalizedKubeconfigPathOverride(_ pathOverride: String?) -> String? {
        guard let pathOverride else {
            return nil
        }

        let normalized = pathOverride
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ":")

        return normalized.isEmpty ? nil : normalized
    }

    func connectSelectedCluster() {
        guard let selectedClusterID else { return }

        connectionTask?.cancel()
        cancelResourceListTasks()
        cancelResourceWatchTasks()
        resourceDetailTask?.cancel()
        cancelResourceDetailWatchTasks()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelPodLogTask()
        cancelEnvSecretValueTasks()
        stopPortForwardSessions { $0.contextID == selectedClusterID }
        connectionErrorMessage = nil
        connectionProgressMessage = nil
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
                    kubeconfig: kubeconfig,
                    progress: { [weak model = self] progress in
                        await model?.updateConnectionProgress(contextID: selectedClusterID, progress: progress)
                    }
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
        cancelResourceDetailWatchTasks()
        resourceEventsTask?.cancel()
        cancelDashboardMetricsTask()
        cancelPodLogTask()
        cancelEnvSecretValueTasks()
        stopPortForwardSessions { $0.contextID == selectedClusterID }
        connectionTask = nil
        resourceDetailTask = nil
        resourceDetailWatchTasksByQuery.removeAll()
        resourceEventsTask = nil
        dashboardMetricsTask = nil
        podLogTask = nil
        connectionErrorMessage = nil
        connectionProgressMessage = nil
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
            resourceWatchStatusByQuery = resourceWatchStatusByQuery.filter { $0.key.contextID != selectedClusterID }
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

    func resourceWatchStatus(for resource: ResourceNavigationItem) -> ResourceWatchStatus? {
        guard let query = resourceListQuery(for: resource),
              shouldWatchResourceList(query) else {
            return nil
        }

        return resourceWatchStatusByQuery[query] ?? .idle
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
        cancelResourceWatchFlush(query: query)
        resourceWatchStatusByQuery[query] = .idle
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
        sinceSeconds: Int? = nil,
        follow: Bool = false
    ) -> PodLogLoadState {
        guard let query = podLogQuery(
            for: pod,
            containerName: containerName,
            timestamps: timestamps,
            previous: previous,
            tailLines: tailLines,
            sinceSeconds: sinceSeconds,
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
        sinceSeconds: Int? = nil,
        follow: Bool = false
    ) -> String {
        guard let pod,
              let query = podLogQuery(
                for: pod,
                containerName: containerName,
                timestamps: timestamps,
                previous: previous,
                tailLines: tailLines,
                sinceSeconds: sinceSeconds,
                follow: follow
              ) else {
            return "\(selectedClusterID ?? "none")|logs|none|\(containerName ?? "")|\(timestamps)|\(previous)|\(tailLines.map(String.init) ?? "all")|\(sinceSeconds.map(String.init) ?? "any")|\(follow)"
        }

        return query.id
    }

    func loadPodLogs(
        for pod: KubernetesUnstructuredResource,
        containerName: String?,
        timestamps: Bool = true,
        previous: Bool = false,
        tailLines: Int? = 200,
        sinceSeconds: Int? = nil,
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
                sinceSeconds: sinceSeconds,
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
        tailLines: Int?,
        sinceSeconds: Int? = nil
    ) async throws -> String {
        guard selectedConnectionState == .connected,
              let query = podLogQuery(
                for: pod,
                containerName: containerName,
                timestamps: timestamps,
                previous: previous,
                tailLines: tailLines,
                sinceSeconds: sinceSeconds,
                follow: false
              ) else {
            throw KubernetesClientError.unavailable("Connect to a cluster before loading pod logs.")
        }

        guard let logService else {
            return Self.sanitizedPodLogText(PreviewKubernetesLogService.previewLogText)
        }

        let text = try await logService.podLogs(
            contextName: query.contextID,
            kubeconfig: loadedKubeconfig,
            namespace: query.namespace,
            podName: query.podName,
            options: podLogOptions(for: query)
        )
        return Self.sanitizedPodLogText(text)
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
        [
            resourceDetailQuery(for: resource, row: row)?.id ?? "\(selectedClusterID ?? "none")|\(resource.id)|\(row.id)",
            row.metadata.resourceVersion ?? "no-resource-version"
        ].joined(separator: "|")
    }

    func loadResourceDetail(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        force: Bool = false
    ) {
        guard selectedConnectionState == .connected,
              let query = resourceDetailQuery(for: resource, row: row) else {
            return
        }

        loadResourceDetail(query: query, row: row, force: force)
    }

    func previewMutation(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        proposedYAML: String
    ) async throws -> KubernetesMutationPreview {
        guard let mutationPreviewService else {
            throw MutationPreviewRequestError.unavailable
        }
        guard selectedConnectionState == .connected else {
            throw MutationPreviewRequestError.disconnected
        }
        guard let selectedClusterID else {
            throw MutationPreviewRequestError.missingCluster
        }
        guard let discoveredResource = resource.discoveredResource(in: selectedDiscovery) else {
            throw MutationPreviewRequestError.missingResource
        }
        guard let name = row.metadata.name, !name.isEmpty else {
            throw MutationPreviewRequestError.missingName
        }

        let namespace = discoveredResource.namespaced ? row.metadata.namespace : nil
        let kubeconfig = loadedKubeconfig
        return try await mutationPreviewService.previewExistingResource(
            contextName: selectedClusterID,
            kubeconfig: kubeconfig,
            resource: discoveredResource,
            namespace: namespace,
            name: name,
            proposedYAML: proposedYAML
        )
    }

    func applyMutation(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        preview: KubernetesMutationPreview
    ) async throws -> KubernetesResourceDetail {
        guard let mutationPreviewService else {
            throw MutationPreviewRequestError.unavailable
        }
        guard selectedConnectionState == .connected else {
            throw MutationPreviewRequestError.disconnected
        }
        guard let selectedClusterID else {
            throw MutationPreviewRequestError.missingCluster
        }
        guard let query = resourceDetailQuery(for: resource, row: row) else {
            throw MutationPreviewRequestError.missingResource
        }

        let kubeconfig = loadedKubeconfig
        let appliedResource = try await mutationPreviewService.applyExistingResource(
            contextName: selectedClusterID,
            kubeconfig: kubeconfig,
            preview: preview
        )
        let summary: KubernetesResourceDetailSummary
        if let resourceDetailService {
            summary = await Self.expandedEnvironmentSummary(
                for: appliedResource,
                query: query,
                kubeconfig: kubeconfig,
                resourceDetailService: resourceDetailService,
                configMapResource: ResourceNavigationItem.configMaps.discoveredResource(in: selectedDiscovery),
                secretResource: ResourceNavigationItem.secrets.discoveredResource(in: selectedDiscovery)
            )
        } else {
            summary = appliedResource.summary
        }
        finishResourceDetail(query: query, detail: appliedResource, summary: summary)
        loadResourceList(for: resource, force: true)
        return appliedResource
    }

    func canScaleResource(_ resource: ResourceNavigationItem, row: KubernetesUnstructuredResource) -> Bool {
        guard canRunMutations,
              ["Deployment", "StatefulSet"].contains(resource.discoveredResource(in: selectedDiscovery)?.kind ?? row.displayKind),
              resource.discoveredResource(in: selectedDiscovery)?.verbs.contains("patch") == true else {
            return false
        }
        return true
    }

    func canRestartRollout(_ resource: ResourceNavigationItem, row: KubernetesUnstructuredResource) -> Bool {
        guard canRunMutations,
              ["Deployment", "StatefulSet", "DaemonSet"].contains(resource.discoveredResource(in: selectedDiscovery)?.kind ?? row.displayKind),
              resource.discoveredResource(in: selectedDiscovery)?.verbs.contains("patch") == true else {
            return false
        }
        return true
    }

    func canDeleteResource(_ resource: ResourceNavigationItem, row: KubernetesUnstructuredResource) -> Bool {
        guard canRunMutations,
              row.metadata.name?.isEmpty == false,
              resource.discoveredResource(in: selectedDiscovery)?.verbs.contains("delete") == true else {
            return false
        }
        return true
    }

    func scaleResource(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        replicas: Int
    ) async throws -> KubernetesResourceDetail {
        let target = try mutationTarget(for: resource, row: row, requiredVerb: "patch")
        guard ["Deployment", "StatefulSet"].contains(target.discoveredResource.kind) else {
            throw MutationActionRequestError.unsupportedAction("Only Deployments and StatefulSets can be scaled here.")
        }

        let recordID = startMutationAction(
            kind: .scale,
            contextID: target.contextID,
            namespace: target.namespace,
            resourceKind: target.discoveredResource.kind,
            resourceName: target.name,
            detail: "Replicas: \(replicas)"
        )

        do {
            let detail = try await target.service.scale(
                contextName: target.contextID,
                kubeconfig: target.kubeconfig,
                resource: target.discoveredResource,
                namespace: target.namespace,
                name: target.name,
                replicas: replicas
            )
            await finishSuccessfulResourceMutation(
                recordID: recordID,
                resource: resource,
                row: row,
                target: target,
                detail: detail
            )
            return detail
        } catch {
            finishMutationAction(recordID, status: .failed(error.localizedDescription))
            throw error
        }
    }

    func restartRollout(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource
    ) async throws -> KubernetesResourceDetail {
        let target = try mutationTarget(for: resource, row: row, requiredVerb: "patch")
        guard ["Deployment", "StatefulSet", "DaemonSet"].contains(target.discoveredResource.kind) else {
            throw MutationActionRequestError.unsupportedAction("Rollout restart is available for Deployments, StatefulSets, and DaemonSets.")
        }

        let recordID = startMutationAction(
            kind: .restart,
            contextID: target.contextID,
            namespace: target.namespace,
            resourceKind: target.discoveredResource.kind,
            resourceName: target.name,
            detail: "Patched pod template restart annotation"
        )

        do {
            let detail = try await target.service.restartRollout(
                contextName: target.contextID,
                kubeconfig: target.kubeconfig,
                resource: target.discoveredResource,
                namespace: target.namespace,
                name: target.name,
                restartedAt: Date()
            )
            await finishSuccessfulResourceMutation(
                recordID: recordID,
                resource: resource,
                row: row,
                target: target,
                detail: detail
            )
            return detail
        } catch {
            finishMutationAction(recordID, status: .failed(error.localizedDescription))
            throw error
        }
    }

    func deleteResource(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource
    ) async throws {
        let target = try mutationTarget(for: resource, row: row, requiredVerb: "delete")
        let recordID = startMutationAction(
            kind: target.discoveredResource.kind == "Namespace" ? .delete : .delete,
            contextID: target.contextID,
            namespace: target.namespace,
            resourceKind: target.discoveredResource.kind,
            resourceName: target.name,
            detail: "Delete requested"
        )

        do {
            _ = try await target.service.delete(
                contextName: target.contextID,
                kubeconfig: target.kubeconfig,
                resource: target.discoveredResource,
                namespace: target.namespace,
                name: target.name
            )
            finishMutationAction(recordID, status: .succeeded)
            loadResourceList(for: resource, force: true)
        } catch {
            finishMutationAction(recordID, status: .failed(error.localizedDescription))
            throw error
        }
    }

    func applyManifestYAML(_ yaml: String, actionKind: MutationActionKind = .apply) async throws -> KubernetesResourceDetail {
        let target = try manifestMutationTarget(for: yaml)
        let recordID = startMutationAction(
            kind: actionKind,
            contextID: target.contextID,
            namespace: target.namespace,
            resourceKind: target.resource.kind,
            resourceName: target.name,
            detail: "Server-side apply"
        )

        do {
            let detail = try await target.service.applyManifest(
                contextName: target.contextID,
                kubeconfig: target.kubeconfig,
                resource: target.resource,
                namespace: target.namespace,
                name: target.name,
                yaml: yaml,
                dryRun: false
            )
            finishMutationAction(recordID, status: .succeeded)
            if let item = ResourceNavigationItem.navigationItem(forOwnerKind: target.resource.kind) {
                loadResourceList(for: item, force: true)
            }
            return detail
        } catch {
            finishMutationAction(recordID, status: .failed(error.localizedDescription))
            throw error
        }
    }

    func previewApplyManifestYAML(_ yaml: String) async throws -> KubernetesManifestApplyPreview {
        let target = try manifestMutationTarget(for: yaml)
        let dryRunResource = try await target.service.applyManifest(
            contextName: target.contextID,
            kubeconfig: target.kubeconfig,
            resource: target.resource,
            namespace: target.namespace,
            name: target.name,
            yaml: yaml,
            dryRun: true
        )

        let liveYAML: String
        if target.resource.verbs.contains("get"), let resourceDetailService {
            do {
                liveYAML = try await resourceDetailService.resourceDetail(
                    contextName: target.contextID,
                    kubeconfig: target.kubeconfig,
                    resource: target.resource,
                    namespace: target.namespace,
                    name: target.name
                ).yaml
            } catch {
                liveYAML = ""
            }
        } else {
            liveYAML = ""
        }

        return KubernetesManifestApplyPreview(
            contextID: target.contextID,
            resource: target.resource,
            namespace: target.namespace,
            name: target.name,
            dryRunResource: dryRunResource,
            diff: KubernetesYAMLDiff.between(old: liveYAML, new: dryRunResource.yaml)
        )
    }

    private func loadResourceDetail(
        query: ResourceDetailQuery,
        row: KubernetesUnstructuredResource,
        force: Bool = false,
        restartDetailWatch: Bool = true
    ) {
        guard selectedConnectionState == .connected,
              query.resource.verbs.contains("get") else {
            return
        }

        if !force {
            switch resourceDetailStateByQuery[query] {
            case .some(.loaded(let snapshot)) where isResourceDetailSnapshot(snapshot, currentFor: row):
                return
            case .some(.loading):
                return
            case .some(.loaded), .some(.idle), .some(.failed), .none:
                break
            }
        }

        resourceDetailTask?.cancel()
        if restartDetailWatch {
            cancelResourceDetailWatch(query: query)
        }
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

    private func isResourceDetailSnapshot(
        _ snapshot: ResourceDetailSnapshot,
        currentFor row: KubernetesUnstructuredResource
    ) -> Bool {
        guard let rowResourceVersion = row.metadata.resourceVersion,
              !rowResourceVersion.isEmpty else {
            return true
        }

        return snapshot.summary.resourceVersion == rowResourceVersion
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
            if cluster.connectionState == .connecting || cluster.connectionState == .authenticating {
                cluster.connectionState = .disconnected
            }
        }
        if selectedClusterID == contextID {
            connectionProgressMessage = nil
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

        if selectedClusterID == contextID {
            connectionErrorMessage = nil
            connectionProgressMessage = nil
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
            connectionProgressMessage = nil
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

    private func updateConnectionProgress(
        contextID: ClusterSummary.ID,
        progress: KubernetesConnectionProgress
    ) {
        updateCluster(id: contextID) { cluster in
            cluster.connectionState = progress.connectionState
        }
        if selectedClusterID == contextID {
            connectionProgressMessage = progress.message
        }
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
        let reconnectDelays = Self.resourceWatchReconnectDelaysNanoseconds
        recordDiagnostic(
            .debug,
            category: "watch",
            message: "Starting resource watch.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query)
        )
        resourceWatchTasksByQuery[query] = Task.detached(priority: .utility) { [weak self, resourceListService, kubeconfig, namespace, query, resourceVersion, reconnectDelays] in
            var latestResourceVersion = resourceVersion
            var failureCount = 0
            var attempt = 1

            do {
                while true {
                    try Task.checkCancellation()
                    guard self != nil else {
                        return
                    }

                    await self?.startResourceWatchAttempt(query: query, attempt: attempt)

                    do {
                        for try await event in resourceListService.watchResources(
                            contextName: query.contextID,
                            kubeconfig: kubeconfig,
                            resource: query.resource,
                            namespace: namespace,
                            resourceVersion: latestResourceVersion
                        ) {
                            try Task.checkCancellation()
                            if event.type == .error {
                                throw KubernetesClientError.statusCode(event.status?.code ?? 0, event.status?.message)
                            }
                            latestResourceVersion = await self?.applyResourceWatchEvent(event, query: query) ?? latestResourceVersion
                        }

                        try Task.checkCancellation()
                        failureCount = 0
                        attempt += 1
                        let delay = reconnectDelays.first ?? 500_000_000
                        await self?.scheduleResourceWatchReconnect(
                            query: query,
                            attempt: attempt,
                            delayNanoseconds: delay,
                            message: nil
                        )
                        try await Task.sleep(nanoseconds: delay)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if Self.isExpiredResourceVersionError(error) {
                            await self?.recordResourceWatchRelist(query: query, error: error)
                            await self?.cancelResourceWatchFlush(query: query)
                            do {
                                let response = try await resourceListService.listResources(
                                    contextName: query.contextID,
                                    kubeconfig: kubeconfig,
                                    resource: query.resource,
                                    namespace: namespace
                                )
                                try Task.checkCancellation()
                                latestResourceVersion = await self?.relistResourceAfterExpiredWatch(
                                    query: query,
                                    response: response
                                ) ?? response.metadata?.resourceVersion
                                failureCount = 0
                                attempt += 1
                                continue
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                failureCount += 1
                                await self?.recordResourceWatchFailure(query: query, error: error)
                                guard Self.shouldRetryResourceWatch(
                                    error: error,
                                    failureCount: failureCount,
                                    retryBudget: reconnectDelays.count
                                ) else {
                                    await self?.failResourceWatch(query: query, message: error.localizedDescription)
                                    return
                                }

                                attempt += 1
                                let delay = Self.resourceWatchReconnectDelay(
                                    failureCount: failureCount,
                                    reconnectDelays: reconnectDelays
                                )
                                await self?.scheduleResourceWatchReconnect(
                                    query: query,
                                    attempt: attempt,
                                    delayNanoseconds: delay,
                                    message: error.localizedDescription
                                )
                                try await Task.sleep(nanoseconds: delay)
                                continue
                            }
                        }

                        failureCount += 1
                        await self?.recordResourceWatchFailure(query: query, error: error)
                        guard Self.shouldRetryResourceWatch(
                            error: error,
                            failureCount: failureCount,
                            retryBudget: reconnectDelays.count
                        ) else {
                            await self?.failResourceWatch(query: query, message: error.localizedDescription)
                            return
                        }

                        attempt += 1
                        let delay = Self.resourceWatchReconnectDelay(
                            failureCount: failureCount,
                            reconnectDelays: reconnectDelays
                        )
                        await self?.scheduleResourceWatchReconnect(
                            query: query,
                            attempt: attempt,
                            delayNanoseconds: delay,
                            message: error.localizedDescription
                        )
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
            } catch is CancellationError {
                await self?.cancelResourceWatch(query: query)
            } catch {
                await self?.failResourceWatch(query: query, message: error.localizedDescription)
            }
        }
    }

    private func startActiveResourceWatchIfPossible() {
        guard let selectedResource,
              let query = resourceListQuery(for: selectedResource),
              case .loaded(let snapshot) = resourceListStateByQuery[query] else {
            return
        }

        startResourceWatchIfNeeded(query: query, resourceVersion: snapshot.resourceVersion)
    }

    nonisolated private static func isExpiredResourceVersionError(_ error: Error) -> Bool {
        if case KubernetesClientError.statusCode(410, _) = error {
            return true
        }

        return false
    }

    nonisolated private static func shouldRetryResourceWatch(
        error: Error,
        failureCount: Int,
        retryBudget: Int
    ) -> Bool {
        isTransientResourceWatchError(error) || failureCount <= retryBudget
    }

    nonisolated private static func isTransientResourceWatchError(_ error: Error) -> Bool {
        switch error {
        case KubernetesClientError.unavailable:
            return true
        case KubernetesClientError.statusCode(let code, _):
            return code == 429 || (500..<600).contains(code)
        default:
            return false
        }
    }

    nonisolated private static func resourceWatchReconnectDelay(
        failureCount: Int,
        reconnectDelays: [UInt64]
    ) -> UInt64 {
        guard !reconnectDelays.isEmpty else {
            return 1_000_000_000
        }

        let index = min(max(failureCount - 1, 0), reconnectDelays.count - 1)
        return reconnectDelays[index]
    }

    private func relistResourceAfterExpiredWatch(
        query: ResourceListQuery,
        response: KubernetesUnstructuredResourceList
    ) -> String? {
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
        markResourceWatchLive(query: query, eventAt: Date())
        recordDiagnostic(
            .info,
            category: "watch",
            message: "Resource watch relisted after expired resource version.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging([
                "itemCount": "\(items.count)",
                "resourceVersion": response.metadata?.resourceVersion ?? "-"
            ]) { _, new in new }
        )
        return response.metadata?.resourceVersion
    }

    private func applyResourceWatchEvent(
        _ event: KubernetesWatchEvent<KubernetesUnstructuredResource>,
        query: ResourceListQuery
    ) -> String? {
        guard case .loaded(let snapshot) = resourceListStateByQuery[query] else {
            return resourceVersion(from: event)
        }

        let eventAt = Date()
        markResourceWatchLive(query: query, eventAt: eventAt)
        enqueueResourceWatchEvent(event, query: query, eventAt: eventAt)
        return resourceVersion(from: event) ?? snapshot.resourceVersion
    }

    private func enqueueResourceWatchEvent(
        _ event: KubernetesWatchEvent<KubernetesUnstructuredResource>,
        query: ResourceListQuery,
        eventAt: Date
    ) {
        var batch = pendingResourceWatchBatchesByQuery[query] ?? ResourceWatchEventBatch()
        batch.events.append(event)
        batch.lastEventAt = eventAt
        pendingResourceWatchBatchesByQuery[query] = batch
        scheduleResourceWatchFlush(query: query)
    }

    private func scheduleResourceWatchFlush(query: ResourceListQuery) {
        guard resourceWatchFlushTasksByQuery[query] == nil else {
            return
        }

        let delay = Self.resourceWatchFlushDelayNanoseconds
        resourceWatchFlushTasksByQuery[query] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
                self?.flushPendingResourceWatchEvents(query: query)
            } catch is CancellationError {
                self?.cancelResourceWatchFlush(query: query)
            } catch {
                self?.cancelResourceWatchFlush(query: query)
            }
        }
    }

    private func flushPendingResourceWatchEvents(query: ResourceListQuery) {
        resourceWatchFlushTasksByQuery[query] = nil
        guard let batch = pendingResourceWatchBatchesByQuery.removeValue(forKey: query),
              !batch.events.isEmpty else {
            return
        }

        applyResourceWatchEvents(batch.events, query: query, eventAt: batch.lastEventAt)
    }

    private func cancelResourceWatchFlush(query: ResourceListQuery) {
        resourceWatchFlushTasksByQuery[query]?.cancel()
        resourceWatchFlushTasksByQuery[query] = nil
        pendingResourceWatchBatchesByQuery[query] = nil
    }

    private func applyResourceWatchEvents(
        _ events: [KubernetesWatchEvent<KubernetesUnstructuredResource>],
        query: ResourceListQuery,
        eventAt: Date
    ) {
        guard case .loaded(var snapshot) = resourceListStateByQuery[query] else {
            return
        }

        markResourceWatchLive(query: query, eventAt: eventAt)
        var detailRefreshCandidatesByID: [KubernetesUnstructuredResource.ID: KubernetesUnstructuredResource] = [:]

        for event in events {
            switch event.type {
            case .added, .modified:
                guard let object = event.object else {
                    continue
                }
                let item = normalizedResource(object, for: query)
                detailRefreshCandidatesByID[item.id] = item
                if let index = snapshot.items.firstIndex(where: { $0.id == item.id }) {
                    snapshot.items[index] = item
                } else {
                    snapshot.items.append(item)
                }
                snapshot.resourceVersion = item.metadata.resourceVersion ?? snapshot.resourceVersion
            case .deleted:
                guard let object = event.object else {
                    continue
                }
                let item = normalizedResource(object, for: query)
                detailRefreshCandidatesByID[item.id] = nil
                snapshot.items.removeAll { $0.id == item.id }
                snapshot.resourceVersion = item.metadata.resourceVersion ?? snapshot.resourceVersion
            case .bookmark:
                if let resourceVersion = event.object?.metadata.resourceVersion {
                    snapshot.resourceVersion = resourceVersion
                }
            case .error:
                continue
            }
        }

        snapshot.loadedAt = eventAt
        resourceListStateByQuery[query] = .loaded(snapshot)
        for detailRefreshCandidate in detailRefreshCandidatesByID.values {
            refreshLoadedDetailIfStale(row: detailRefreshCandidate, listQuery: query)
        }
    }

    private func resourceVersion(from event: KubernetesWatchEvent<KubernetesUnstructuredResource>) -> String? {
        event.object?.metadata.resourceVersion
    }

    private func refreshLoadedDetailIfStale(
        row: KubernetesUnstructuredResource,
        listQuery: ResourceListQuery
    ) {
        guard selectedConnectionState == .connected,
              listQuery.resource.verbs.contains("get"),
              let name = row.metadata.name,
              !name.isEmpty else {
            return
        }

        let namespace = namespaceForDetailRequest(
            row: row,
            resource: listQuery.resource,
            namespaceSelection: listQuery.namespaceSelection
        )
        if listQuery.resource.namespaced, namespace == nil {
            return
        }

        let detailQuery = ResourceDetailQuery(
            contextID: listQuery.contextID,
            resource: listQuery.resource,
            namespace: namespace,
            name: name
        )

        guard case .loaded(let snapshot) = resourceDetailStateByQuery[detailQuery],
              !isResourceDetailSnapshot(snapshot, currentFor: row) else {
            return
        }

        loadResourceDetail(query: detailQuery, row: row)
    }

    private func startResourceDetailWatchIfNeeded(
        query: ResourceDetailQuery,
        resourceVersion: String?
    ) {
        guard shouldWatchResourceDetail(query),
              resourceDetailWatchTasksByQuery[query] == nil,
              let detailWatchService = resourceListService as? KubernetesResourceDetailWatchServicing else {
            return
        }

        let kubeconfig = loadedKubeconfig
        let reconnectDelays = Self.resourceWatchReconnectDelaysNanoseconds
        recordDiagnostic(
            .debug,
            category: "watch",
            message: "Starting resource detail watch.",
            contextID: query.contextID,
            metadata: resourceDetailDiagnosticsMetadata(query)
        )

        resourceDetailWatchTasksByQuery[query] = Task.detached(priority: .utility) { [weak self, detailWatchService, kubeconfig, query, resourceVersion, reconnectDelays] in
            var latestResourceVersion = resourceVersion
            var failureCount = 0

            do {
                while true {
                    try Task.checkCancellation()
                    guard self != nil else {
                        return
                    }

                    do {
                        for try await event in detailWatchService.watchResource(
                            contextName: query.contextID,
                            kubeconfig: kubeconfig,
                            resource: query.resource,
                            namespace: query.namespace,
                            name: query.name,
                            resourceVersion: latestResourceVersion
                        ) {
                            try Task.checkCancellation()
                            if event.type == .error {
                                throw KubernetesClientError.statusCode(event.status?.code ?? 0, event.status?.message)
                            }
                            latestResourceVersion = await self?.applyResourceDetailWatchEvent(event, query: query) ?? latestResourceVersion
                        }

                        try Task.checkCancellation()
                        failureCount = 0
                        let delay = reconnectDelays.first ?? 500_000_000
                        try await Task.sleep(nanoseconds: delay)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if Self.isExpiredResourceVersionError(error) {
                            await self?.recordResourceDetailWatchRelist(query: query, error: error)
                            latestResourceVersion = nil
                            failureCount = 0
                            continue
                        }

                        failureCount += 1
                        await self?.recordResourceDetailWatchFailure(query: query, error: error)
                        guard Self.shouldRetryResourceWatch(
                            error: error,
                            failureCount: failureCount,
                            retryBudget: reconnectDelays.count
                        ) else {
                            await self?.finishResourceDetailWatch(query: query)
                            return
                        }

                        let delay = Self.resourceWatchReconnectDelay(
                            failureCount: failureCount,
                            reconnectDelays: reconnectDelays
                        )
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
            } catch is CancellationError {
                await self?.cancelResourceDetailWatch(query: query)
            } catch {
                await self?.recordResourceDetailWatchFailure(query: query, error: error)
                await self?.finishResourceDetailWatch(query: query)
            }
        }
    }

    private func applyResourceDetailWatchEvent(
        _ event: KubernetesWatchEvent<KubernetesUnstructuredResource>,
        query: ResourceDetailQuery
    ) -> String? {
        switch event.type {
        case .added, .modified:
            guard let object = event.object else {
                return nil
            }

            let item = normalizedResource(object, for: query)
            guard isResourceDetailWatchObject(item, query: query) else {
                return item.metadata.resourceVersion
            }

            guard case .loaded(let snapshot) = resourceDetailStateByQuery[query],
                  !isResourceDetailSnapshot(snapshot, currentFor: item) else {
                return item.metadata.resourceVersion
            }

            loadResourceDetail(
                query: query,
                row: item,
                force: true,
                restartDetailWatch: false
            )
            return item.metadata.resourceVersion
        case .deleted:
            guard let object = event.object else {
                return nil
            }

            let item = normalizedResource(object, for: query)
            guard isResourceDetailWatchObject(item, query: query) else {
                return item.metadata.resourceVersion
            }

            resourceDetailStateByQuery[query] = .failed("Resource was deleted.")
            cancelResourceDetailWatch(query: query)
            return item.metadata.resourceVersion
        case .bookmark:
            return event.object?.metadata.resourceVersion
        case .error:
            return nil
        }
    }

    private func normalizedResource(
        _ resource: KubernetesUnstructuredResource,
        for query: ResourceDetailQuery
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

    private func isResourceDetailWatchObject(
        _ row: KubernetesUnstructuredResource,
        query: ResourceDetailQuery
    ) -> Bool {
        guard row.metadata.name == query.name else {
            return false
        }

        guard query.resource.namespaced else {
            return true
        }

        return row.metadata.namespace == query.namespace
    }

    private func shouldWatchResourceDetail(_ query: ResourceDetailQuery) -> Bool {
        resourceWatchesEnabled &&
            selectedClusterID == query.contextID &&
            selectedConnectionState == .connected &&
            query.resource.verbs.contains("watch")
    }

    private func recordResourceDetailWatchFailure(query: ResourceDetailQuery, error: Error) {
        recordDiagnostic(
            .warning,
            category: "watch",
            message: "Resource detail watch failed.",
            contextID: query.contextID,
            metadata: resourceDetailDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func recordResourceDetailWatchRelist(query: ResourceDetailQuery, error: Error) {
        recordDiagnostic(
            .info,
            category: "watch",
            message: "Resource detail watch resource version expired; reconnecting without resourceVersion.",
            contextID: query.contextID,
            metadata: resourceDetailDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func finishResourceDetailWatch(query: ResourceDetailQuery) {
        resourceDetailWatchTasksByQuery[query] = nil
    }

    private func cancelResourceDetailWatch(query: ResourceDetailQuery) {
        resourceDetailWatchTasksByQuery[query]?.cancel()
        resourceDetailWatchTasksByQuery[query] = nil
    }

    private func startResourceWatchAttempt(query: ResourceListQuery, attempt: Int) {
        let now = Date()
        resourceWatchStatusByQuery[query] = .live(since: now, lastEventAt: nil)
    }

    private func markResourceWatchLive(query: ResourceListQuery, eventAt: Date) {
        let since: Date
        if case .live(let currentSince, _) = resourceWatchStatusByQuery[query] {
            since = currentSince
        } else {
            since = eventAt
        }

        resourceWatchStatusByQuery[query] = .live(since: since, lastEventAt: eventAt)
    }

    private func scheduleResourceWatchReconnect(
        query: ResourceListQuery,
        attempt: Int,
        delayNanoseconds: UInt64,
        message: String?
    ) {
        let nextRetryAt = Date().addingTimeInterval(TimeInterval(delayNanoseconds) / 1_000_000_000)
        resourceWatchStatusByQuery[query] = .reconnecting(
            ResourceWatchReconnectState(
                attempt: attempt,
                nextRetryAt: nextRetryAt,
                message: message
            )
        )
    }

    private func finishResourceWatch(query: ResourceListQuery) {
        resourceWatchTasksByQuery[query] = nil
        resourceWatchStatusByQuery[query] = .stale(
            ResourceWatchStaleState(
                endedAt: Date(),
                message: "Watch paused after reconnect attempts. Refresh to resume live updates."
            )
        )
    }

    private func cancelResourceWatch(query: ResourceListQuery) {
        resourceWatchTasksByQuery[query] = nil
        resourceWatchStatusByQuery[query] = .idle
    }

    private func recordResourceWatchFailure(query: ResourceListQuery, error: Error) {
        recordDiagnostic(
            .warning,
            category: "watch",
            message: "Resource watch failed.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func recordResourceWatchRelist(query: ResourceListQuery, error: Error) {
        recordDiagnostic(
            .info,
            category: "watch",
            message: "Resource watch resource version expired; relisting.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging(errorDiagnosticsMetadata(error)) { _, new in new }
        )
    }

    private func failResourceWatch(query: ResourceListQuery, message: String) {
        resourceWatchTasksByQuery[query] = nil
        resourceWatchStatusByQuery[query] = .failed(
            ResourceWatchFailureState(
                failedAt: Date(),
                message: message
            )
        )
        recordDiagnostic(
            .warning,
            category: "watch",
            message: "Resource watch stopped after reconnect attempts.",
            contextID: query.contextID,
            metadata: resourceListDiagnosticsMetadata(query).merging(["error": message]) { _, new in new }
        )
    }

    private func shouldWatchResourceList(_ query: ResourceListQuery) -> Bool {
        guard resourceWatchesEnabled,
              selectedClusterID == query.contextID,
              query.resource.verbs.contains("list"),
              query.resource.verbs.contains("watch"),
              let selectedResource,
              selectedResource.requiresDiscoveredResource,
              let activeResource = selectedResource.discoveredResource(in: selectedDiscovery) else {
            return false
        }

        return activeResource.id == query.resource.id
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
        let sanitizedText = Self.sanitizedPodLogText(text)
        podLogTask = nil
        podLogStateByQuery[query] = .loaded(
            PodLogSnapshot(
                query: query,
                text: Self.cappedPodLogText(sanitizedText, lineLimit: podLogLineLimit),
                loadedAt: Date()
            )
        )
        recordDiagnostic(
            .info,
            category: "logs",
            message: "Pod logs loaded.",
            contextID: query.contextID,
            metadata: podLogDiagnosticsMetadata(query).merging([
                "lineCount": "\(sanitizedText.split(separator: "\n", omittingEmptySubsequences: false).count)",
                "lineLimit": "\(podLogLineLimit)"
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
            sinceSeconds: query.sinceSeconds,
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
                text: Self.cappedPodLogText(
                    Self.sanitizedPodLogText(currentText + chunk),
                    lineLimit: podLogLineLimit
                ),
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

    private func recapLoadedPodLogs(lineLimit: Int) {
        podLogStateByQuery = podLogStateByQuery.mapValues { state in
            guard case .loaded(let snapshot) = state else {
                return state
            }

            return .loaded(
                PodLogSnapshot(
                    query: snapshot.query,
                    text: Self.cappedPodLogText(snapshot.text, lineLimit: lineLimit),
                    loadedAt: snapshot.loadedAt
                )
            )
        }
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
        startResourceDetailWatchIfNeeded(query: query, resourceVersion: summary.resourceVersion)
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
        let cancelledQueries = Array(resourceWatchTasksByQuery.keys)
        resourceWatchTasksByQuery.values.forEach { $0.cancel() }
        resourceWatchTasksByQuery.removeAll()
        resourceWatchFlushTasksByQuery.values.forEach { $0.cancel() }
        resourceWatchFlushTasksByQuery.removeAll()
        pendingResourceWatchBatchesByQuery.removeAll()
        for query in cancelledQueries {
            resourceWatchStatusByQuery[query] = .idle
        }
    }

    private func cancelResourceDetailWatchTasks() {
        resourceDetailWatchTasksByQuery.values.forEach { $0.cancel() }
        resourceDetailWatchTasksByQuery.removeAll()
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

    private func stopPortForwardSessions(where shouldStop: (PortForwardSession) -> Bool) {
        for session in portForwardSessions where session.isActive && shouldStop(session) {
            portForwardHandlesBySessionID[session.id]?.stop()
            updatePortForwardSession(session.id) { session in
                session.status = .stopped
            }
        }
    }

    private func finishPortForwardSession(
        _ sessionID: PortForwardSession.ID,
        termination: KubernetesPortForwardTermination
    ) {
        portForwardHandlesBySessionID[sessionID] = nil
        updatePortForwardSession(sessionID) { session in
            if session.status == .stopped {
                return
            }
            if termination.userStopped || termination.exitCode == 0 {
                session.status = .stopped
            } else {
                let message = termination.message.map { ": \($0)" } ?? ""
                session.status = .failed(
                    explainedPortForwardFailureMessage("kubectl exited with code \(termination.exitCode)\(message)")
                )
            }
        }
    }

    private func failPortForwardSession(_ sessionID: PortForwardSession.ID, message: String) {
        portForwardHandlesBySessionID[sessionID] = nil
        updatePortForwardSession(sessionID) { session in
            session.status = .failed(explainedPortForwardFailureMessage(message))
        }
    }

    private func updatePortForwardSession(
        _ sessionID: PortForwardSession.ID,
        _ update: (inout PortForwardSession) -> Void
    ) {
        guard let index = portForwardSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        update(&portForwardSessions[index])
    }

    private func updateExecLaunch(
        _ launchID: ExecLaunchRecord.ID,
        _ update: (inout ExecLaunchRecord) -> Void
    ) {
        guard let index = execLaunches.firstIndex(where: { $0.id == launchID }) else {
            return
        }

        update(&execLaunches[index])
    }

    private func explainedPortForwardFailureMessage(_ message: String) -> String {
        DebugActionFailureExplanation.explain(message, action: .portForward)
    }

    private func explainedExecFailureMessage(_ message: String) -> String {
        DebugActionFailureExplanation.explain(message, action: .exec)
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
        sinceSeconds: Int?,
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
            sinceSeconds: follow ? nil : sinceSeconds,
            timestamps: timestamps,
            follow: follow
        )
    }

    private func kubeconfigPath(forContextID contextID: String) -> String? {
        loadedKubeconfig.contexts.first { $0.name == contextID }?.source.url.path
    }

    private func podLogOptions(for query: PodLogQuery) -> KubernetesPodLogOptions {
        KubernetesPodLogOptions(
            container: query.containerName,
            previous: query.previous,
            follow: query.follow,
            tailLines: query.follow ? 0 : query.tailLines,
            sinceSeconds: query.follow ? nil : query.sinceSeconds,
            timestamps: query.timestamps
        )
    }

    private static func sanitizedPodLogText(_ text: String) -> String {
        LogTextSanitizer.stripANSISequences(from: text)
    }

    private static func cappedPodLogText(_ text: String, lineLimit: Int) -> String {
        let hasTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hasTrailingNewline {
            lines.removeLast()
        }

        guard lines.count > lineLimit else {
            return text
        }

        let cappedText = lines.suffix(lineLimit).joined(separator: "\n")
        return hasTrailingNewline ? cappedText + "\n" : cappedText
    }

    nonisolated private static func clampedPodLogLineLimit(_ lineLimit: Int) -> Int {
        max(1, min(lineLimit, 50_000))
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

    private func mutationTarget(
        for resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        requiredVerb: String
    ) throws -> MutationActionTarget {
        guard let mutationActionService else {
            throw MutationActionRequestError.unavailable
        }
        guard selectedConnectionState == .connected else {
            throw MutationActionRequestError.disconnected
        }
        guard let selectedClusterID else {
            throw MutationActionRequestError.missingCluster
        }
        guard let discoveredResource = resource.discoveredResource(in: selectedDiscovery) else {
            throw MutationActionRequestError.missingResource
        }
        guard discoveredResource.verbs.contains(requiredVerb) else {
            throw MutationActionRequestError.unsupportedAction("The Kubernetes API did not advertise \(requiredVerb) support for \(discoveredResource.kind).")
        }
        guard let name = row.metadata.name, !name.isEmpty else {
            throw MutationActionRequestError.missingName
        }

        let namespace = namespaceForDetailRequest(row: row, resource: discoveredResource)
        if discoveredResource.namespaced, namespace == nil {
            throw MutationActionRequestError.missingResource
        }

        return MutationActionTarget(
            service: mutationActionService,
            contextID: selectedClusterID,
            kubeconfig: loadedKubeconfig,
            discoveredResource: discoveredResource,
            namespace: namespace,
            name: name
        )
    }

    private func manifestMutationTarget(for yaml: String) throws -> ManifestMutationTarget {
        guard let mutationActionService else {
            throw MutationActionRequestError.unavailable
        }
        guard selectedConnectionState == .connected else {
            throw MutationActionRequestError.disconnected
        }
        guard let selectedClusterID else {
            throw MutationActionRequestError.missingCluster
        }
        guard let discovery = selectedDiscovery else {
            throw MutationActionRequestError.missingDiscovery
        }

        let manifest = try KubernetesMutationManifest(yaml: yaml)
        guard let resource = discovery.discoveredResources.first(where: {
            $0.groupVersion == manifest.apiVersion && $0.kind == manifest.kind
        }) else {
            throw MutationActionRequestError.invalidManifestTarget
        }
        try manifest.validateApplyTarget(resource: resource)
        guard resource.verbs.contains("patch") else {
            throw MutationActionRequestError.unsupportedAction("The Kubernetes API did not advertise patch support for \(resource.kind).")
        }
        guard let name = manifest.name, !name.isEmpty else {
            throw MutationActionRequestError.missingName
        }

        return ManifestMutationTarget(
            service: mutationActionService,
            contextID: selectedClusterID,
            kubeconfig: loadedKubeconfig,
            resource: resource,
            namespace: resource.namespaced ? manifest.namespace : nil,
            name: name
        )
    }

    private func finishSuccessfulResourceMutation(
        recordID: MutationActionRecord.ID,
        resource: ResourceNavigationItem,
        row: KubernetesUnstructuredResource,
        target: MutationActionTarget,
        detail: KubernetesResourceDetail
    ) async {
        finishMutationAction(recordID, status: .succeeded)

        if let query = resourceDetailQuery(for: resource, row: row) {
            let summary: KubernetesResourceDetailSummary
            if let resourceDetailService {
                summary = await Self.expandedEnvironmentSummary(
                    for: detail,
                    query: query,
                    kubeconfig: target.kubeconfig,
                    resourceDetailService: resourceDetailService,
                    configMapResource: ResourceNavigationItem.configMaps.discoveredResource(in: selectedDiscovery),
                    secretResource: ResourceNavigationItem.secrets.discoveredResource(in: selectedDiscovery)
                )
            } else {
                summary = detail.summary
            }
            finishResourceDetail(query: query, detail: detail, summary: summary)
        }

        loadResourceList(for: resource, force: true)
    }

    private func startMutationAction(
        kind: MutationActionKind,
        contextID: ClusterSummary.ID,
        namespace: String?,
        resourceKind: String,
        resourceName: String,
        detail: String
    ) -> MutationActionRecord.ID {
        let id = UUID()
        mutationActionHistory.insert(
            MutationActionRecord(
                id: id,
                kind: kind,
                contextID: contextID,
                namespace: namespace,
                resourceKind: resourceKind,
                resourceName: resourceName,
                detail: detail,
                startedAt: Date(),
                finishedAt: nil,
                status: .running
            ),
            at: 0
        )
        if mutationActionHistory.count > 50 {
            mutationActionHistory.removeLast(mutationActionHistory.count - 50)
        }
        return id
    }

    private func finishMutationAction(
        _ id: MutationActionRecord.ID,
        status: MutationActionStatus
    ) {
        guard let index = mutationActionHistory.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutationActionHistory[index].status = status
        mutationActionHistory[index].finishedAt = Date()
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
            involvedUID: detail.summary.uid,
            involvedResourceVersion: detail.summary.resourceVersion
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
        namespaceForDetailRequest(
            row: row,
            resource: resource,
            namespaceSelection: selectedNamespaceSelection
        )
    }

    private func namespaceForDetailRequest(
        row: KubernetesUnstructuredResource,
        resource: KubernetesDiscoveredResource,
        namespaceSelection: String
    ) -> String? {
        guard resource.namespaced else {
            return nil
        }

        if let namespace = row.metadata.namespace, !namespace.isEmpty {
            return namespace
        }

        guard namespaceSelection != Self.allNamespacesSelection else {
            return nil
        }

        return namespaceSelection
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

    private func saveAIProviderSettings(
        _ settings: AIProviderSettings,
        reason: String,
        resetAvailability: Bool = true
    ) {
        aiProviderSettings = settings
        userPreferences.aiProviderSettings = settings
        aiModelDiscoveryTask?.cancel()
        if resetAvailability {
            invalidateAIProviderReachability()
        }
        recordDiagnostic(
            .info,
            category: "ai",
            message: reason,
            metadata: [
                "shape": settings.shape.rawValue,
                "preset": settings.preset.rawValue,
                "hasModel": settings.selectedModelID == nil ? "false" : "true"
            ]
        )
    }

    private func invalidateAIProviderReachability() {
        aiModelDiscoveryTask?.cancel()
        aiAvailabilityTask?.cancel()
        aiModelDiscoveryState = .idle
        aiAvailabilityState = .unknown
    }

    private func finishAIModelDiscovery(_ models: [AIModelInfo]) {
        aiModelDiscoveryState = .loaded(models)
        aiAvailabilityState = .available("\(models.count.formatted()) models available.")
        if let selectedModelID = aiProviderSettings.selectedModelID,
           !models.contains(where: { $0.id == selectedModelID }) {
            setAISelectedModelID(nil)
        }
        recordDiagnostic(
            .info,
            category: "ai",
            message: "AI models loaded.",
            metadata: ["count": "\(models.count)"]
        )
    }

    private func cancelAIModelDiscovery() {
        if aiModelDiscoveryState == .loading {
            aiModelDiscoveryState = .idle
        }
        if aiAvailabilityState == .checking {
            aiAvailabilityState = .unknown
        }
    }

    private func failAIModelDiscovery(_ error: Error) {
        aiModelDiscoveryState = .failed(error.localizedDescription)
        aiAvailabilityState = .unavailable(error.localizedDescription)
        recordDiagnostic(
            .warning,
            category: "ai",
            message: "AI model discovery failed.",
            metadata: ["error": error.localizedDescription]
        )
    }

    private func finishAIAvailability(_ message: String) {
        aiAvailabilityState = .available(message)
        recordDiagnostic(.info, category: "ai", message: "AI provider availability test succeeded.")
    }

    private func aiLogSnapshots(for detail: ResourceDetailSnapshot) -> [PodLogSnapshot] {
        let summary = detail.summary
        let kind = summary.kind ?? detail.query.resource.kind
        guard kind == "Pod" else {
            return []
        }

        guard let namespace = summary.namespace ?? detail.query.namespace else {
            return []
        }
        let name = summary.name ?? detail.query.name
        return podLogStateByQuery.compactMap { query, state in
            guard query.contextID == detail.query.contextID,
                  query.namespace == namespace,
                  query.podName == name,
                  case .loaded(let snapshot) = state else {
                return nil
            }

            return snapshot
        }
        .sorted { lhs, rhs in
            lhs.query.title.localizedStandardCompare(rhs.query.title) == .orderedAscending
        }
    }

    private func gatherAIResourceEvents(for detail: ResourceDetailSnapshot) async -> (state: ResourceEventsLoadState, notes: [String]) {
        guard selectedConnectionState == .connected else {
            return (.failed("Connect to a cluster before loading events."), ["Skipped event lookup because the cluster is not connected."])
        }

        guard let query = resourceEventsQuery(for: detail),
              query.eventsResource.verbs.contains("list") else {
            return (resourceEventsState(for: detail), ["Skipped event lookup because events are not discoverable for this resource."])
        }

        if case .loaded(let snapshot) = resourceEventsStateByQuery[query] {
            if snapshot.events.isEmpty {
                return (.loaded(snapshot), ["Checked Kubernetes events for this resource; none were reported."])
            }
            return (.loaded(snapshot), ["Reused \(snapshot.events.count) already loaded Kubernetes event(s) for this resource."])
        }

        guard let resourceEventService else {
            return (.failed("Resource event service is unavailable."), ["Tried to read Kubernetes events, but the event service is unavailable."])
        }

        do {
            let response = try await resourceEventService.resourceEvents(
                contextName: query.contextID,
                kubeconfig: loadedKubeconfig,
                eventsResource: query.eventsResource,
                namespace: query.namespace,
                involvedKind: query.involvedKind,
                involvedName: query.involvedName,
                involvedUID: query.involvedUID
            )
            let snapshot = ResourceEventsSnapshot(
                query: query,
                events: response.summaries,
                resourceVersion: response.metadata?.resourceVersion,
                loadedAt: Date()
            )
            resourceEventsStateByQuery[query] = .loaded(snapshot)
            if snapshot.events.isEmpty {
                return (.loaded(snapshot), ["Checked Kubernetes events for this resource; none were reported."])
            }
            return (.loaded(snapshot), ["Read \(snapshot.events.count) Kubernetes event(s) for this resource."])
        } catch {
            let message = error.localizedDescription
            resourceEventsStateByQuery[query] = .failed(message)
            return (.failed(message), ["Tried to read Kubernetes events, but it failed: \(message)"])
        }
    }

    private func shouldGatherPodLogs(for detail: ResourceDetailSnapshot, userPrompt: String) -> Bool {
        let kind = detail.summary.kind ?? detail.query.resource.kind
        guard kind == "Pod" else {
            return false
        }

        if aiPromptIndicatesLogIntent(userPrompt) {
            return true
        }

        return detail.summary.containers.contains { ($0.restartCount ?? 0) > 0 || $0.ready == false }
    }

    private func aiPromptIndicatesLogIntent(_ userPrompt: String) -> Bool {
        let prompt = userPrompt.lowercased()
        let logIntentFragments = [
            "log",
            "logs",
            "лог",
            "логи",
            "логов",
            "логах",
            "suspicious",
            "подозр",
            "error",
            "ошиб",
            "exception",
            "исключ",
            "crash",
            "restart",
            "рестарт",
            "readiness",
            "liveness",
            "debug",
            "дебаг",
            "why",
            "почему",
            "fail",
            "failure",
            "не работает",
            "слом",
            "not working",
            "analyze"
        ]
        return logIntentFragments.contains { prompt.contains($0) }
    }

    private func gatherAIPodLogs(for detail: ResourceDetailSnapshot, userPrompt: String) async -> (snapshots: [PodLogSnapshot], notes: [String]) {
        guard selectedConnectionState == .connected,
              let selectedClusterID else {
            return ([], ["Skipped pod log reads because the cluster is not connected."])
        }

        let summary = detail.summary
        let kind = summary.kind ?? detail.query.resource.kind
        guard kind == "Pod" else {
            return ([], ["Skipped pod log reads because the selected resource is \(kind)."])
        }

        guard let namespace = summary.namespace ?? detail.query.namespace,
              !namespace.isEmpty else {
            return ([], ["Skipped pod log reads because the pod namespace is unknown."])
        }

        let podName = summary.name ?? detail.query.name
        let containers = aiLogContainers(for: detail)
        guard !containers.isEmpty else {
            return ([], ["Skipped pod log reads because no pod containers were found in the manifest."])
        }

        let wantsPreviousLogs = shouldGatherPreviousPodLogs(for: detail, userPrompt: userPrompt)
        var snapshots: [PodLogSnapshot] = []
        var notes: [String] = []

        for container in containers.prefix(5) {
            let current = await gatherAIPodLogSnapshot(
                contextID: selectedClusterID,
                namespace: namespace,
                podName: podName,
                containerName: container.name,
                previous: false
            )
            snapshots.append(contentsOf: current.snapshot.map { [$0] } ?? [])
            notes.append(current.note)

            guard wantsPreviousLogs else {
                continue
            }

            let previous = await gatherAIPodLogSnapshot(
                contextID: selectedClusterID,
                namespace: namespace,
                podName: podName,
                containerName: container.name,
                previous: true
            )
            snapshots.append(contentsOf: previous.snapshot.map { [$0] } ?? [])
            notes.append(previous.note)
        }

        if containers.count > 5 {
            notes.append("Skipped \(containers.count - 5) additional container log stream(s) to keep the AI context bounded.")
        }

        return (snapshots, notes)
    }

    private func gatherAIRelatedPodContext(
        for detail: ResourceDetailSnapshot,
        userPrompt: String
    ) async -> (context: AIRelatedPodContext?, notes: [String]) {
        let kind = detail.summary.kind ?? detail.query.resource.kind
        guard shouldGatherRelatedPods(for: kind),
              let selector = detail.summary.labelSelector else {
            return (nil, [])
        }

        guard selectedConnectionState == .connected,
              let selectedClusterID else {
            return (nil, ["Skipped related Pod lookup because the cluster is not connected."])
        }

        guard let namespace = detail.summary.namespace ?? detail.query.namespace,
              !namespace.isEmpty else {
            return (nil, ["Skipped related Pod lookup because the selected resource namespace is unknown."])
        }

        guard let podResource = ResourceNavigationItem.pods.discoveredResource(in: selectedDiscovery),
              podResource.verbs.contains("list") else {
            return (nil, ["Skipped related Pod lookup because Pods are not discoverable or listable."])
        }

        guard let resourceListService else {
            return (nil, ["Tried to read related Pods, but the resource list service is unavailable."])
        }

        do {
            let response: KubernetesUnstructuredResourceList
            if let filteredService = resourceListService as? KubernetesResourceFilteredListServicing {
                response = try await filteredService.listResources(
                    contextName: selectedClusterID,
                    kubeconfig: loadedKubeconfig,
                    resource: podResource,
                    namespace: namespace,
                    labelSelector: selector.queryString
                )
            } else {
                let unfiltered = try await resourceListService.listResources(
                    contextName: selectedClusterID,
                    kubeconfig: loadedKubeconfig,
                    resource: podResource,
                    namespace: namespace
                )
                response = KubernetesUnstructuredResourceList(
                    apiVersion: unfiltered.apiVersion,
                    kind: unfiltered.kind,
                    metadata: unfiltered.metadata,
                    items: unfiltered.items.filter { selector.matches(labels: $0.metadata.labels) }
                )
            }

            let pods = response.items.sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            var notes = ["Read \(pods.count) related Pod(s) for selector \(selector.displayText)."]
            guard !pods.isEmpty else {
                return (
                    AIRelatedPodContext(
                        title: "Related Pod Health",
                        content: "Selector: \(AIContextRedactor.redactedText(selector.displayText))\nNo Pods currently match this selector.",
                        logSnapshots: []
                    ),
                    notes
                )
            }

            var contentLines = [
                "Selector: \(AIContextRedactor.redactedText(selector.displayText))",
                "Related Pods: \(pods.count)"
            ]
            let unhealthyPods = pods.filter(aiShouldInspectRelatedPod)
            if !unhealthyPods.isEmpty {
                contentLines.append("Pods needing attention: \(unhealthyPods.count)")
                notes.append("Found \(unhealthyPods.count) related Pod(s) needing attention: \(unhealthyPods.prefix(3).map(\.displayName).joined(separator: ", ")).")
            }
            contentLines.append("")
            contentLines.append(contentsOf: pods.prefix(12).map(aiRelatedPodLine))
            if pods.count > 12 {
                contentLines.append("- \(pods.count - 12) additional matching Pod(s) omitted from AI context.")
            }

            let wantsRelatedPodLogs = aiPromptIndicatesLogIntent(userPrompt)
            var inspectionPods = Array(unhealthyPods.prefix(3))
            if wantsRelatedPodLogs {
                let remainingSlots = max(0, 3 - inspectionPods.count)
                let selectedIDs = Set(inspectionPods.map(\.id))
                inspectionPods.append(
                    contentsOf: pods
                        .filter { !selectedIDs.contains($0.id) }
                        .prefix(remainingSlots)
                )
                if unhealthyPods.isEmpty {
                    notes.append("Prompt asked for logs/runtime evidence, so Vibekube inspected related Pod logs for up to 3 matching Pod(s).")
                }
            }
            var logSnapshots: [PodLogSnapshot] = []
            for pod in inspectionPods {
                let eventResult = await gatherAIEventsForPod(
                    contextID: selectedClusterID,
                    podResource: podResource,
                    pod: pod
                )
                notes.append(eventResult.note)
                if !eventResult.events.isEmpty {
                    contentLines.append("")
                    contentLines.append("Events for Pod/\(pod.displayName):")
                    contentLines.append(contentsOf: eventResult.events.prefix(5).map { "- \(AIContextRedactor.redactedText($0.type)) reason=\(AIContextRedactor.redactedText($0.reason)) message=\(AIContextRedactor.redactedText($0.message))" })
                }

                let logResult = await gatherAILogsForRelatedPod(
                    contextID: selectedClusterID,
                    pod: pod,
                    userPrompt: userPrompt
                )
                logSnapshots.append(contentsOf: logResult.snapshots)
                notes.append(contentsOf: logResult.notes)
            }

            if unhealthyPods.count > inspectionPods.count {
                notes.append("Skipped deep AI event/log reads for \(unhealthyPods.count - inspectionPods.count) additional unhealthy related Pod(s) to keep context bounded.")
            }
            if wantsRelatedPodLogs, pods.count > inspectionPods.count {
                notes.append("Skipped related Pod log reads for \(pods.count - inspectionPods.count) additional matching Pod(s) to keep the AI context bounded.")
            }

            return (
                AIRelatedPodContext(
                    title: "Related Pod Health",
                    content: contentLines.joined(separator: "\n"),
                    logSnapshots: logSnapshots
                ),
                notes
            )
        } catch {
            return (nil, ["Tried to read related Pods for selector \(selector.displayText), but it failed: \(error.localizedDescription)"])
        }
    }

    private func shouldGatherRelatedPods(for kind: String) -> Bool {
        switch kind {
        case "Deployment", "ReplicaSet", "StatefulSet", "DaemonSet", "Job", "Service":
            true
        default:
            false
        }
    }

    private func aiShouldInspectRelatedPod(_ pod: KubernetesUnstructuredResource) -> Bool {
        let status = pod.displayStatus.lowercased()
        let failedStatusFragments = [
            "backoff",
            "error",
            "failed",
            "errimagepull",
            "crashloop",
            "invalidimage",
            "createcontainer",
            "pending"
        ]
        if failedStatusFragments.contains(where: { status.contains($0) }) {
            return true
        }

        let readyCount = aiPodReadyCount(pod)
        let containerCount = aiPodContainerCount(pod)
        if containerCount > 0, readyCount < containerCount {
            return true
        }

        return aiPodContainerStatuses(pod).contains { status in
            status["ready"]?.boolValue == false ||
                (status["restartCount"]?.intValue ?? 0) > 0 ||
                aiContainerStateNeedsAttention(status["state"]) ||
                status["lastState"]?.objectValue?.isEmpty == false
        }
    }

    private func aiRelatedPodLine(_ pod: KubernetesUnstructuredResource) -> String {
        let containerStatuses = aiPodContainerStatuses(pod)
        let containers = containerStatuses.prefix(4).map { status in
            let name = status["name"]?.stringValue ?? "container"
            let ready = status["ready"]?.boolValue.map(String.init) ?? "unknown"
            let restarts = status["restartCount"]?.intValue.map(String.init) ?? "unknown"
            let state = aiContainerStateText(status["state"])
            return "\(name) ready=\(ready) restarts=\(restarts) state=\(state)"
        }
        let containersText = containers.isEmpty ? "" : " containers=[\(containers.joined(separator: "; "))]"
        return "- Pod/\(pod.displayName) status=\(AIContextRedactor.redactedText(pod.displayStatus)) ready=\(aiPodReadyDescription(pod)) restarts=\(aiPodRestartCount(pod))\(containersText)"
    }

    private func gatherAIEventsForPod(
        contextID: ClusterSummary.ID,
        podResource: KubernetesDiscoveredResource,
        pod: KubernetesUnstructuredResource
    ) async -> (events: [KubernetesResourceEventSummary], note: String) {
        guard let eventsResource = ResourceNavigationItem.events.discoveredResource(in: selectedDiscovery),
              eventsResource.verbs.contains("list") else {
            return ([], "Skipped events for related Pod/\(pod.displayName) because events are not discoverable.")
        }

        let query = ResourceEventsQuery(
            contextID: contextID,
            eventsResource: eventsResource,
            namespace: pod.metadata.namespace,
            involvedKind: podResource.kind,
            involvedName: pod.displayName,
            involvedUID: pod.metadata.uid,
            involvedResourceVersion: pod.metadata.resourceVersion
        )

        if case .loaded(let snapshot) = resourceEventsStateByQuery[query] {
            let note = snapshot.events.isEmpty
                ? "Checked events for related Pod/\(pod.displayName); none were reported."
                : "Reused \(snapshot.events.count) event(s) for related Pod/\(pod.displayName)."
            return (snapshot.events, note)
        }

        guard let resourceEventService else {
            return ([], "Tried to read events for related Pod/\(pod.displayName), but the event service is unavailable.")
        }

        do {
            let response = try await resourceEventService.resourceEvents(
                contextName: contextID,
                kubeconfig: loadedKubeconfig,
                eventsResource: eventsResource,
                namespace: query.namespace,
                involvedKind: query.involvedKind,
                involvedName: query.involvedName,
                involvedUID: query.involvedUID
            )
            let snapshot = ResourceEventsSnapshot(
                query: query,
                events: response.summaries,
                resourceVersion: response.metadata?.resourceVersion,
                loadedAt: Date()
            )
            resourceEventsStateByQuery[query] = .loaded(snapshot)
            let note = snapshot.events.isEmpty
                ? "Checked events for related Pod/\(pod.displayName); none were reported."
                : "Read \(snapshot.events.count) event(s) for related Pod/\(pod.displayName)."
            return (snapshot.events, note)
        } catch {
            let message = error.localizedDescription
            resourceEventsStateByQuery[query] = .failed(message)
            return ([], "Tried to read events for related Pod/\(pod.displayName), but it failed: \(message)")
        }
    }

    private func gatherAILogsForRelatedPod(
        contextID: ClusterSummary.ID,
        pod: KubernetesUnstructuredResource,
        userPrompt: String
    ) async -> (snapshots: [PodLogSnapshot], notes: [String]) {
        guard let namespace = pod.metadata.namespace,
              !namespace.isEmpty else {
            return ([], ["Skipped logs for related Pod/\(pod.displayName) because its namespace is unknown."])
        }

        let statuses = aiPodContainerStatuses(pod)
        let unhealthyStatuses = statuses.filter { status in
            status["ready"]?.boolValue == false ||
                (status["restartCount"]?.intValue ?? 0) > 0 ||
                aiContainerStateNeedsAttention(status["state"])
        }
        let selectedStatuses = (unhealthyStatuses.isEmpty ? statuses : unhealthyStatuses).prefix(3)
        guard !selectedStatuses.isEmpty else {
            return ([], ["Skipped logs for related Pod/\(pod.displayName) because no container statuses were found."])
        }

        var snapshots: [PodLogSnapshot] = []
        var notes: [String] = []
        for status in selectedStatuses {
            let containerName = status["name"]?.stringValue
            let current = await gatherAIPodLogSnapshot(
                contextID: contextID,
                namespace: namespace,
                podName: pod.displayName,
                containerName: containerName,
                previous: false
            )
            snapshots.append(contentsOf: current.snapshot.map { [$0] } ?? [])
            notes.append(current.note)

            if shouldGatherPreviousPodLogs(for: pod, userPrompt: userPrompt) {
                let previous = await gatherAIPodLogSnapshot(
                    contextID: contextID,
                    namespace: namespace,
                    podName: pod.displayName,
                    containerName: containerName,
                    previous: true
                )
                snapshots.append(contentsOf: previous.snapshot.map { [$0] } ?? [])
                notes.append(previous.note)
            }
        }

        return (snapshots, notes)
    }

    private func shouldGatherPreviousPodLogs(for pod: KubernetesUnstructuredResource, userPrompt: String) -> Bool {
        let prompt = userPrompt.lowercased()
        let previousIntentFragments = [
            "previous",
            "last",
            "crash",
            "crashloop",
            "restart",
            "terminated",
            "exit"
        ]
        if previousIntentFragments.contains(where: { prompt.contains($0) }) {
            return true
        }

        return aiPodRestartCount(pod) > 0 || aiPodContainerStatuses(pod).contains { $0["lastState"]?.objectValue?.isEmpty == false }
    }

    private func aiPodReadyCount(_ pod: KubernetesUnstructuredResource) -> Int {
        aiPodContainerStatuses(pod).filter { $0["ready"]?.boolValue == true }.count
    }

    private func aiPodContainerCount(_ pod: KubernetesUnstructuredResource) -> Int {
        let statusCount = aiPodContainerStatuses(pod).count
        if statusCount > 0 {
            return statusCount
        }
        return pod.spec?["containers"]?.arrayValue?.count ?? 0
    }

    private func aiPodReadyDescription(_ pod: KubernetesUnstructuredResource) -> String {
        let containerCount = aiPodContainerCount(pod)
        guard containerCount > 0 else {
            return "-"
        }
        return "\(aiPodReadyCount(pod))/\(containerCount)"
    }

    private func aiPodRestartCount(_ pod: KubernetesUnstructuredResource) -> Int {
        aiPodContainerStatuses(pod).reduce(0) { result, status in
            result + (status["restartCount"]?.intValue ?? 0)
        }
    }

    private func aiPodContainerStatuses(_ pod: KubernetesUnstructuredResource) -> [[String: KubernetesJSONValue]] {
        let initStatuses = pod.status?["initContainerStatuses"]?.arrayValue ?? []
        let appStatuses = pod.status?["containerStatuses"]?.arrayValue ?? []
        let ephemeralStatuses = pod.status?["ephemeralContainerStatuses"]?.arrayValue ?? []
        return (appStatuses + initStatuses + ephemeralStatuses).compactMap(\.objectValue)
    }

    private func aiContainerStateNeedsAttention(_ value: KubernetesJSONValue?) -> Bool {
        let state = aiContainerStateText(value).lowercased()
        return state.contains("backoff") ||
            state.contains("error") ||
            state.contains("failed") ||
            state.contains("errimagepull") ||
            state.contains("crashloop") ||
            state.contains("invalidimage") ||
            state.contains("createcontainer") ||
            state.contains("terminated")
    }

    private func aiContainerStateText(_ value: KubernetesJSONValue?) -> String {
        guard let state = value?.objectValue else {
            return "unknown"
        }
        if let waiting = state["waiting"]?.objectValue {
            let reason = waiting["reason"]?.stringValue ?? "Waiting"
            let message = waiting["message"]?.stringValue.map { " \($0)" } ?? ""
            return AIContextRedactor.redactedText("\(reason)\(message)")
        }
        if let terminated = state["terminated"]?.objectValue {
            let reason = terminated["reason"]?.stringValue ?? "Terminated"
            let exitCode = terminated["exitCode"]?.intValue.map { " exitCode=\($0)" } ?? ""
            let message = terminated["message"]?.stringValue.map { " \($0)" } ?? ""
            return AIContextRedactor.redactedText("\(reason)\(exitCode)\(message)")
        }
        if state["running"]?.objectValue != nil {
            return "Running"
        }
        return "unknown"
    }

    private func aiLogContainers(for detail: ResourceDetailSnapshot) -> [KubernetesContainerSummary] {
        let containers = detail.summary.containers
        let appContainers = containers.filter { $0.kind == .container }
        let initContainers = containers.filter { $0.kind == .initContainer }
        let ephemeralContainers = containers.filter { $0.kind == .ephemeralContainer }
        return appContainers + initContainers + ephemeralContainers
    }

    private func shouldGatherPreviousPodLogs(for detail: ResourceDetailSnapshot, userPrompt: String) -> Bool {
        let prompt = userPrompt.lowercased()
        let previousIntentFragments = [
            "previous",
            "last",
            "crash",
            "crashloop",
            "restart",
            "terminated",
            "exit"
        ]
        if previousIntentFragments.contains(where: { prompt.contains($0) }) {
            return true
        }

        return detail.summary.containers.contains { ($0.restartCount ?? 0) > 0 || $0.lastState != nil }
    }

    private func gatherAIPodLogSnapshot(
        contextID: ClusterSummary.ID,
        namespace: String,
        podName: String,
        containerName: String?,
        previous: Bool
    ) async -> (snapshot: PodLogSnapshot?, note: String) {
        let query = PodLogQuery(
            contextID: contextID,
            namespace: namespace,
            podName: podName,
            containerName: containerName,
            previous: previous,
            tailLines: 300,
            sinceSeconds: nil,
            timestamps: true,
            follow: false
        )
        let label = "\(previous ? "previous" : "current") logs for \(query.title)"

        do {
            let text: String
            if let logService {
                text = try await logService.podLogs(
                    contextName: query.contextID,
                    kubeconfig: loadedKubeconfig,
                    namespace: query.namespace,
                    podName: query.podName,
                    options: podLogOptions(for: query)
                )
            } else {
                text = PreviewKubernetesLogService.previewLogText
            }

            let sanitized = Self.cappedPodLogText(
                Self.sanitizedPodLogText(text),
                lineLimit: min(podLogLineLimit, 300)
            )
            let snapshot = PodLogSnapshot(query: query, text: sanitized, loadedAt: Date())
            podLogStateByQuery[query] = .loaded(snapshot)

            let lineCount = snapshot.lines.filter { !$0.isEmpty }.count
            if lineCount == 0 {
                return (snapshot, "Read \(label); Kubernetes returned no log lines.")
            }
            return (snapshot, "Read \(lineCount) line(s) of \(label).")
        } catch {
            let message = error.localizedDescription
            podLogStateByQuery[query] = .failed(message)
            return (nil, "Tried to read \(label), but it failed: \(message)")
        }
    }

    private func mergedLogSnapshots(_ snapshots: [PodLogSnapshot]) -> [PodLogSnapshot] {
        var byQuery: [PodLogQuery: PodLogSnapshot] = [:]
        for snapshot in snapshots {
            byQuery[snapshot.query] = snapshot
        }
        return byQuery.values.sorted { lhs, rhs in
            if lhs.query.title == rhs.query.title {
                return lhs.query.previous && !rhs.query.previous
            }
            return lhs.query.title.localizedStandardCompare(rhs.query.title) == .orderedAscending
        }
    }

    private func cancelAIAvailability() {
        if aiAvailabilityState == .checking {
            aiAvailabilityState = .unknown
        }
    }

    private func failAIAvailability(_ error: Error) {
        aiAvailabilityState = .unavailable(error.localizedDescription)
        recordDiagnostic(
            .warning,
            category: "ai",
            message: "AI provider availability test failed.",
            metadata: ["error": error.localizedDescription]
        )
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
            "tailLines": query.tailLines.map(String.init) ?? "all",
            "sinceSeconds": query.sinceSeconds.map(String.init) ?? "any"
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

        return ResourceNavigationItem(rawValue: id)
    }
}

private struct PreviewKubernetesConnectionService: KubernetesConnectionServicing {
    func connect(
        contextName: String,
        kubeconfig: Kubeconfig,
        progress: @escaping @Sendable (KubernetesConnectionProgress) async -> Void
    ) async throws -> KubernetesConnectionSnapshot {
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
