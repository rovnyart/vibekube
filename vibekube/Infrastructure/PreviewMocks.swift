import Foundation

struct PreviewClusterRegistry: ClusterRegistry {
    let clusters: [ClusterSummary] = ClusterSummary.preview
}

struct PreviewConnectionManager: ConnectionManaging {
    func connect(to cluster: ClusterSummary) async throws {}
    func disconnect(from cluster: ClusterSummary) {}
}

struct PreviewResourceStore: ResourceStoring {
    func refresh() async throws {}
}

struct PreviewUserPreferences: UserPreferencesProviding {
    var selectedContextID: String?
    var selectedResourceID: String?
    var selectedNamespaceByContextID: [String: String] = [:]
    var diagnosticsFileLoggingEnabled = false
    var diagnosticsIncludeClusterNames = false
    var diagnosticsRetentionDays = 7
}
