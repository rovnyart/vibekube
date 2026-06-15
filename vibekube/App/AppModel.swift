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

    private let kubeconfigLoader: KubeconfigLoader?
    private let connectionService: KubernetesConnectionServicing?
    private var loadedKubeconfig: Kubeconfig
    private var connectionTask: Task<Void, Never>?

    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        if environment["VIBEKUBE_USE_PREVIEW_CLUSTERS"] == "1" {
            self.init(
                clusters: ClusterSummary.preview,
                kubeconfigState: .loaded(contextCount: ClusterSummary.preview.count, sourceCount: 1),
                kubeconfigLoader: nil,
                connectionService: nil
            )
        } else {
            self.init(
                clusters: [],
                kubeconfigState: .notLoaded,
                kubeconfigLoader: KubeconfigLoader(environment: environment),
                connectionService: KubernetesConnectionService()
            )
            reloadKubeconfig()
        }
    }

    init(
        clusters: [ClusterSummary],
        kubeconfigState: KubeconfigDiscoveryState? = nil,
        kubeconfigLoader: KubeconfigLoader? = nil,
        connectionService: KubernetesConnectionServicing? = nil,
        loadedKubeconfig: Kubeconfig? = nil
    ) {
        self.clusters = clusters
        self.selectedClusterID = clusters.first?.id
        self.selectedResource = .dashboard
        self.kubeconfigState = kubeconfigState ?? .loaded(contextCount: clusters.count, sourceCount: 1)
        self.kubeconfigLoader = kubeconfigLoader
        self.connectionService = connectionService
        self.loadedKubeconfig = loadedKubeconfig ?? .empty
    }

    var selectedCluster: ClusterSummary? {
        clusters.first { $0.id == selectedClusterID }
    }

    var selectedConnectionState: ConnectionState {
        selectedCluster?.connectionState ?? .disconnected
    }

    var canConnectSelectedCluster: Bool {
        guard let selectedCluster else { return false }
        return selectedCluster.connectionState.canAttemptConnection
    }

    func selectCluster(id: ClusterSummary.ID?) {
        connectionTask?.cancel()
        selectedClusterID = id
        selectedResource = .dashboard
        connectionErrorMessage = nil
    }

    func selectResource(_ resource: ResourceNavigationItem) {
        selectedResource = resource
    }

    func refresh() {
        reloadKubeconfig()
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
        connectionErrorMessage = nil

        guard let connectionService else {
            updateCluster(id: selectedClusterID) { cluster in
                cluster.connectionState = .connected
                cluster.lastSeenAt = Date()
            }
            return
        }

        let kubeconfig = loadedKubeconfig
        updateCluster(id: selectedClusterID) { cluster in
            cluster.connectionState = .connecting
            cluster.kubernetesVersion = nil
            cluster.lastSeenAt = nil
        }

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
        connectionTask = nil
        connectionErrorMessage = nil

        updateSelectedCluster { cluster in
            cluster.connectionState = .disconnected
            cluster.kubernetesVersion = nil
            cluster.lastSeenAt = nil
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

        if selectedClusterID == contextID {
            connectionErrorMessage = nil
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
}
