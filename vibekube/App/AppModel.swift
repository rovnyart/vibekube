import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var clusters: [ClusterSummary]
    @Published var selectedClusterID: ClusterSummary.ID?
    @Published var selectedResource: ResourceNavigationItem?
    @Published var searchText = ""
    @Published private(set) var lastRefreshedAt: Date?

    convenience init() {
        self.init(clusters: ClusterSummary.preview)
    }

    init(clusters: [ClusterSummary]) {
        self.clusters = clusters
        self.selectedClusterID = clusters.first?.id
        self.selectedResource = .dashboard
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
        lastRefreshedAt = Date()
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
