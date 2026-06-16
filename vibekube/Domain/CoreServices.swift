import Foundation

protocol ClusterRegistry {
    var clusters: [ClusterSummary] { get }
}

protocol ConnectionManaging {
    func connect(to cluster: ClusterSummary) async throws
    func disconnect(from cluster: ClusterSummary)
}

protocol ResourceStoring {
    func refresh() async throws
}

protocol UserPreferencesProviding {
    var selectedContextID: String? { get set }
    var selectedResourceID: String? { get set }
    var selectedNamespaceByContextID: [String: String] { get set }
    var diagnosticsFileLoggingEnabled: Bool { get set }
    var diagnosticsIncludeClusterNames: Bool { get set }
    var diagnosticsRetentionDays: Int { get set }
}
