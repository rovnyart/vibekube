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

    private let kubeconfigLoader: KubeconfigLoader?

    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        if environment["VIBEKUBE_USE_PREVIEW_CLUSTERS"] == "1" {
            self.init(
                clusters: ClusterSummary.preview,
                kubeconfigState: .loaded(contextCount: ClusterSummary.preview.count, sourceCount: 1),
                kubeconfigLoader: nil
            )
        } else {
            self.init(
                clusters: [],
                kubeconfigState: .notLoaded,
                kubeconfigLoader: KubeconfigLoader(environment: environment)
            )
            reloadKubeconfig()
        }
    }

    init(
        clusters: [ClusterSummary],
        kubeconfigState: KubeconfigDiscoveryState? = nil,
        kubeconfigLoader: KubeconfigLoader? = nil
    ) {
        self.clusters = clusters
        self.selectedClusterID = clusters.first?.id
        self.selectedResource = .dashboard
        self.kubeconfigState = kubeconfigState ?? .loaded(contextCount: clusters.count, sourceCount: 1)
        self.kubeconfigLoader = kubeconfigLoader
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
        selectedClusterID = id
        selectedResource = .dashboard
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
        clusters = discoveredClusters

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
        updateSelectedCluster { cluster in
            cluster.connectionState = .connected
            cluster.lastSeenAt = Date()
        }
    }

    func disconnectSelectedCluster() {
        updateSelectedCluster { cluster in
            cluster.connectionState = .disconnected
            cluster.lastSeenAt = nil
        }
    }

    private func updateSelectedCluster(_ update: (inout ClusterSummary) -> Void) {
        guard let selectedClusterID,
              let index = clusters.firstIndex(where: { $0.id == selectedClusterID }) else {
            return
        }

        update(&clusters[index])
    }
}
